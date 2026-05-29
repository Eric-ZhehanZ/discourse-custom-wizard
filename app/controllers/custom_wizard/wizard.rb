# frozen_string_literal: true
class CustomWizard::WizardController < ::CustomWizard::WizardClientController
  requires_plugin "discourse-custom-wizard"

  def show
    if wizard.present?
      mark_approval_seen!(wizard)
      render json: CustomWizard::WizardSerializer.new(wizard, scope: guardian, root: false).as_json,
             status: 200
    else
      render json: { error: I18n.t("wizard.none") }
    end
  end

  # Records that the user has viewed the approval status page and
  # clears the matching `redirect_to_wizard` so they aren't bounced
  # back here on their next navigation. Called from #show — the user
  # is literally looking at the approval notice right now. Refreshing
  # the page is a no-op once the marker is set. Re-approvals reset
  # the marker (see ReviewableCustomWizardSubmission#mark_user_approved!)
  # so a fresh approval triggers the one-shot redirect again.
  def mark_approval_seen!(w)
    return unless w.user
    return unless w.user.custom_fields["wizard_approved_#{w.id}"]
    return if w.user.custom_fields["wizard_approved_seen_#{w.id}"]

    w.user.custom_fields["wizard_approved_seen_#{w.id}"] = true
    if w.user.custom_fields["redirect_to_wizard"].to_s == w.id.to_s
      w.user.custom_fields.delete("redirect_to_wizard")
    end
    w.user.save_custom_fields
  end

  def skip
    params.require(:wizard_id)

    # Soft-skip: a forced wizard that opts into limited skips lets the
    # user dismiss it a bounded number of times before a hard deadline
    # forces completion. We do NOT clear redirect_to_wizard or the
    # submission here (unlike cleanup_on_skip!) — only a snooze is set,
    # so the deadline backstop can still re-engage once it elapses.
    if current_user && CustomWizard::SkipPolicy.enabled?(wizard)
      if CustomWizard::SkipPolicy.can_skip?(current_user, wizard) &&
           CustomWizard::SkipPolicy.record_skip!(current_user, wizard)
        result = {
          success: "OK",
          remaining_skips: CustomWizard::SkipPolicy.skips_remaining(current_user, wizard),
        }
        dest = CustomWizard::Wizard.sanitize_redirect_path(wizard.current_submission&.redirect_to)
        result[:redirect_on_complete] = dest if dest
        return render json: result
      else
        error_key =
          (
            if CustomWizard::SkipPolicy.deadline_passed?(current_user, wizard)
              "wizard.skip_deadline_passed"
            else
              "wizard.no_skip"
            end
          )
        # 422 (not a silent 200) so the client's popupAjaxError surfaces the
        # reason and leaves the user on the wizard. redirect_to_wizard stays
        # set server-side, so completion is still forced.
        return render json: { errors: [I18n.t(error_key)] }, status: 422
      end
    end

    # Delayed-approval users cannot skip the wizard they are locked into.
    # We return a 200 response (not 403) with a structured `locked` flag so
    # the frontend can silently ignore the attempt without triggering
    # `popupAjaxError`. The HTML lockdown + Guardian denial already prevent
    # any actual forum content access, so this endpoint's 4xx status added
    # no real defense — it only caused a confusing dialog to flash on the
    # user's screen. See the `delayed-approval lockdown` threat model in
    # `lib/custom_wizard/extensions/guardian.rb` for the full denylist.
    if current_user && !current_user.staff? &&
         current_user.custom_fields["delayed_approval_wizard_id"] == params[:wizard_id].underscore
      return(render json: { error: I18n.t("wizard.delayed_approval.cannot_skip"), locked: true })
    end

    if wizard.required && !wizard.completed? && wizard.permitted?
      return render json: { error: I18n.t("wizard.no_skip") }
    end

    result = { success: "OK" }

    if current_user && wizard.can_access?
      if redirect_to = wizard.current_submission&.redirect_to
        result.merge!(redirect_to: redirect_to)
      end

      wizard.cleanup_on_skip!
    end

    render json: result
  end

  # One-shot consumption of the stored intent URL. Called by the
  # status page's Continue button: returns a safe destination AND
  # clears submission.redirect_to so the next visit doesn't keep
  # carrying the same destination forward forever.
  #
  # The returned path is always relative (path + query only) — even
  # if the stored value happened to be absolute. This stops a stored
  # cross-origin URL from being handed to DiscourseURL.routeTo as a
  # destination, closing what would otherwise be an open-redirect
  # surface if anything ever managed to set submission.redirect_to
  # to an off-site URL.
  def consume_redirect
    return render json: failed_json unless current_user
    return render json: failed_json unless wizard

    submission = wizard.intent_submission
    raw = submission&.redirect_to.presence
    safe = CustomWizard::Wizard.sanitize_redirect_path(raw)

    if submission && raw
      submission.redirect_to = nil
      submission.save
    end

    # Belt-and-suspenders: the reviewable already clears
    # `redirect_to_wizard` on approval, but stale state can survive in
    # edge cases (manual re-pending, legacy users carrying the field
    # from before approval logic was added, etc.). Without this, the
    # client-side `page:changed` initializer in
    # custom-wizard-redirect.js loops the user back to /w/<id> the
    # moment they navigate away. Only clear when the user has actually
    # passed the gate — never when they are still required to redo the
    # wizard, otherwise this becomes a self-service bypass.
    if !wizard.respond_to?(:required_for_user?) ||
         !wizard.required_for_user?(current_user) ||
         current_user.custom_fields["wizard_approved_#{wizard.id}"]
      if current_user.custom_fields["redirect_to_wizard"].to_s == wizard.id.to_s
        current_user.custom_fields.delete("redirect_to_wizard")
        current_user.save_custom_fields
      end
    end

    render json: { redirect_to: safe || CustomWizard::Wizard.fallback_destination }
  end

  # Self-suspension for users who give up on a denied wizard. We use
  # Discourse's UserSuspender directly rather than the User::Suspend
  # service because the latter goes through a Guardian that disallows
  # users suspending themselves. The suspension is effectively a
  # permanent ban — staff can unsuspend through the standard admin UI
  # to reverse it. Staff are blocked from triggering this on themselves
  # so a moderator can't accidentally lock out the queue handler.
  def deactivate
    raise Discourse::InvalidAccess.new unless current_user
    raise Discourse::InvalidAccess.new if current_user.staff?

    UserSuspender.new(
      current_user,
      suspended_till: 1000.years.from_now,
      reason: I18n.t("wizard.self_suspension_reason"),
      by_user: Discourse.system_user,
    ).suspend

    log_off_user
    render json: { success: true, redirect_to: "/" }
  end

  protected

  def wizard
    @wizard ||=
      begin
        return nil if @builder.blank?
        @builder.build({ reset: params[:reset] }, params)
      end
  end
end

# frozen_string_literal: true
class CustomWizard::WizardController < ::CustomWizard::WizardClientController
  requires_plugin "discourse-custom-wizard"

  def show
    if wizard.present?
      render json: CustomWizard::WizardSerializer.new(wizard, scope: guardian, root: false).as_json,
             status: 200
    else
      render json: { error: I18n.t("wizard.none") }
    end
  end

  def skip
    params.require(:wizard_id)

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

  protected

  def wizard
    @wizard ||=
      begin
        return nil if @builder.blank?
        @builder.build({ reset: params[:reset] }, params)
      end
  end
end

# frozen_string_literal: true

class CustomWizard::WizardSerializer < CustomWizard::BasicWizardSerializer
  attributes :start,
             :background,
             :submission_last_updated_at,
             :theme_id,
             :completed,
             :required,
             :permitted,
             :resume_on_revisit,
             :review_state,
             :pending_review,
             :previously_approved,
             :must_redo,
             :rejection_reason,
             :redirect_back_url,
             :can_deactivate

  has_many :steps, serializer: ::CustomWizard::StepSerializer, embed: :objects
  has_one :user, serializer: ::BasicUserSerializer, embed: :objects

  def completed
    object.completed?
  end

  def include_completed?
    object.completed? &&
      (!object.respond_to?(:multiple_submissions) || !object.multiple_submissions) &&
      !scope.is_admin?
  end

  def permitted
    object.permitted?
  end

  def start
    object.start
  end

  def include_start?
    include_steps? && object.start.present?
  end

  def submission_last_updated_at
    object.current_submission.updated_at
  end

  def include_steps?
    # Always send steps when the wizard is in a review state so the
    # client can transition into the form for re-submission /
    # update-again clicks. Otherwise fall back to "hide once
    # completed".
    return true if review_state != "none"
    !include_completed?
  end

  # One of "none" / "pending" / "approved" / "denied". Drives the
  # user-facing wizard status page.
  def review_state
    return "none" unless object.user
    object.user.custom_fields["wizard_review_state_#{object.id}"].to_s.presence || "none"
  end

  def pending_review
    review_state == "pending"
  end

  def previously_approved
    !!object.user&.custom_fields&.[]("wizard_approved_#{object.id}")
  end

  # True when the user MUST go through the wizard again before regaining
  # site access (denied state, or required-group user without an approved
  # submission). Drives whether the "go to site" button is offered.
  def must_redo
    return false unless object.user
    return false if object.user.staff?
    return true if review_state == "denied"
    !previously_approved && object.respond_to?(:required_for_user?) &&
      object.required_for_user?(object.user)
  end

  # Free-form reason from the most recent rejection — shown verbatim
  # to the user on the denied status page.
  def rejection_reason
    return nil unless review_state == "denied" && object.user

    last_rejection =
      ReviewableCustomWizardSubmission
        .where(created_by_id: object.user.id, status: Reviewable.statuses[:rejected])
        .where("payload ->> 'wizard_id' = ?", object.id)
        .order(updated_at: :desc)
        .first

    last_rejection&.reject_reason.presence
  end

  # URL the user was trying to reach before being redirected to the
  # wizard, captured by CustomWizard::Wizard.set_wizard_redirect. Used
  # as the destination for the "go to site" / "continue" button on the
  # approved status page.
  def redirect_back_url
    object.current_submission&.redirect_to.presence
  end

  # True if this user can self-deactivate via the denied status page.
  # Staff (admins/mods) must not have access to the dangerous deactivate
  # link — they would lock themselves out of moderating the queue.
  def can_deactivate
    !!object.user && !object.user.staff?
  end
end

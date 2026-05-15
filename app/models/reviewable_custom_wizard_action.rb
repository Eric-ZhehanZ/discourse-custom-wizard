# frozen_string_literal: true

# Represents a single wizard action whose effect has been deferred until
# a staff member approves it via the Reviewable queue. The action template
# and a snapshot of the submission fields are captured at submission time
# so the approval is deterministic and survives later edits to the wizard.
class ReviewableCustomWizardAction < Reviewable
  def build_actions(actions, guardian, _args)
    return unless pending?
    return unless guardian.is_staff?

    actions.add(:approve_wizard_action) do |a|
      a.icon = "check"
      a.label = "reviewables.actions.approve_wizard_action.title"
      a.description = "reviewables.actions.approve_wizard_action.description"
    end

    actions.add(:reject_wizard_action) do |a|
      a.icon = "xmark"
      a.label = "reviewables.actions.reject_wizard_action.title"
      a.description = "reviewables.actions.reject_wizard_action.description"
    end
  end

  def perform_approve_wizard_action(_performer, _args)
    apply_pending_action!
    create_result(:success, :approved)
  end

  def perform_reject_wizard_action(_performer, _args)
    create_result(:success, :rejected)
  end

  # Convenience for the queue / API consumers.
  def wizard_id
    payload&.dig("wizard_id")
  end

  def action_id
    payload&.dig("action", "id")
  end

  def action_type
    payload&.dig("action", "type")
  end

  def action_label
    payload&.dig("action", "label").presence || action_id
  end

  private

  def apply_pending_action!
    return if payload.blank?

    user = target&.is_a?(User) ? target : User.find_by(id: target_id)
    return unless user

    wizard_id = payload["wizard_id"]
    action_template = payload["action"]
    return if wizard_id.blank? || action_template.blank?

    builder = CustomWizard::Builder.new(wizard_id, user)
    wizard = builder.build
    return unless wizard

    submission =
      CustomWizard::Submission.new(wizard, payload["submission_fields"] || {})

    CustomWizard::Action.new(
      action: action_template,
      wizard: wizard,
      submission: submission,
    ).perform
  end
end

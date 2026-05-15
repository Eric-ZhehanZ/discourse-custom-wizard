# frozen_string_literal: true

class ReviewableCustomWizardSubmissionSerializer < ReviewableSerializer
  payload_attributes :wizard_id, :submission_id, :submission_fields, :actions

  attributes :wizard_id, :wizard_name, :action_count

  def wizard_id
    object.wizard_id
  end

  def wizard_name
    object.wizard_name
  end

  def action_count
    object.actions_payload.size
  end
end

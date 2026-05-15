# frozen_string_literal: true

class ReviewableCustomWizardActionSerializer < ReviewableSerializer
  payload_attributes :wizard_id,
                     :submission_id,
                     :submission_fields,
                     :action

  attributes :wizard_id, :action_id, :action_type, :action_label

  def wizard_id
    object.wizard_id
  end

  def action_id
    object.action_id
  end

  def action_type
    object.action_type
  end

  def action_label
    object.action_label
  end
end

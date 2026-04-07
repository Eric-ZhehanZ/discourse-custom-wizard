# frozen_string_literal: true

module CustomWizardGuardian
  def can_edit_topic?(topic)
    wizard_can_edit_topic?(topic) || super
  end

  def wizard_can_edit_topic?(topic)
    created_by_wizard = !!topic.wizard_submission_id
    (
      is_my_own?(topic) && created_by_wizard && can_see_topic?(topic) &&
        can_create_post_on_topic?(topic)
    )
  end

  def in_delayed_approval_window?
    return false if @user.blank?
    return false if @user.try(:staff?)
    @user.custom_fields["delayed_approval_wizard_id"].present?
  end

  def can_see_topic?(topic, hide_deleted = true)
    return false if in_delayed_approval_window?
    super
  end

  def can_see_post?(post)
    return false if in_delayed_approval_window?
    super
  end

  def can_create_post?(parent)
    return false if in_delayed_approval_window?
    super
  end

  def can_send_private_message?(target, notify_moderators: false)
    return false if in_delayed_approval_window?
    super
  end

  def can_edit_user?(user)
    return false if in_delayed_approval_window? && @user.id == user.id
    super
  end
end

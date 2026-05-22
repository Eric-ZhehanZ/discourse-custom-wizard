# frozen_string_literal: true
module InvitesControllerCustomWizard
  def path(url)
    return super if url == "/" || @user.blank?

    wizard_id = pending_wizard_id_for(@user)
    if wizard_id
      CustomWizard::Wizard.set_wizard_redirect(@user, wizard_id, url)
      return super("/w/#{wizard_id.dasherize}")
    end

    super
  end

  private def post_process_invite(user)
    super
    @user = user
  end

  # Returns the id of the wizard the user will be forced through after
  # signup, or nil. Checked in order:
  #
  #   1. An already-set `redirect_to_wizard` custom field.
  #   2. An `after_signup` wizard for users who haven't yet seen any
  #      page (the wizard middleware will set redirect_to_wizard on
  #      their next request).
  #   3. A `restrict_to_approved` wizard the user will be locked into
  #      because they're in a required group and haven't been approved.
  #
  # The previous implementation relied on Wizard.user_requires_completion?
  # which only set `redirect_to_wizard` for case 2, leaving case 3 users
  # (the common restrict_to_approved invite flow) with nothing captured.
  private def pending_wizard_id_for(user)
    wid = user.custom_fields["redirect_to_wizard"]
    return wid if wid.present?

    if user.first_seen_at.blank?
      w = CustomWizard::Wizard.after_signup(user)
      return w.id if w && !w.completed?
    end

    CustomWizard::Template.restrict_to_approved_ids.each do |id|
      next if user.custom_fields["wizard_approved_#{id}"]
      w = CustomWizard::Wizard.create(id, user)
      return id if w && w.required_for_user?(user)
    end

    nil
  end
end

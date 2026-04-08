# frozen_string_literal: true
module CustomWizardUsersController
  def account_created
    if current_user.present? && (wizard = CustomWizard::Wizard.after_signup(current_user))
      return redirect_to "/w/#{wizard.id.dasherize}"
    end
    super
  end

  # Block profile writes while the user is locked into a delayed-approval
  # wizard. This replaces the old Guardian `can_edit_user?` override, which
  # was too broad: `can_edit_user?` is also consulted by read-only endpoints
  # like `private_message_topic_tracking_state` that the Ember bootstrap
  # fetches on every page load, so overriding it at the Guardian layer
  # surfaced a 403 popup ("You are not permitted to view the requested
  # resource") as soon as a delayed-approval user hit the wizard page.
  #
  # Gating at the controller level keeps `update` safely locked while
  # letting the data-read endpoints work. The HTML redirect in
  # `redirect_to_wizard_if_required` already prevents the preferences UI
  # from loading for delayed-approval users; this is the API-level defence
  # in depth for a crafted PUT request.
  def update
    if current_user && !current_user.staff? &&
         current_user.custom_fields["delayed_approval_wizard_id"].present?
      raise Discourse::InvalidAccess.new(
              "delayed-approval users cannot update their profile until the wizard is complete",
            )
    end
    super
  end
end

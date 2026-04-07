# frozen_string_literal: true

describe "Delayed approval signup hook" do
  let(:wizard_template) { get_wizard_fixture("wizard") }

  before do
    SiteSetting.must_approve_users = true
    wizard_template["after_signup"] = true
    wizard_template["delay_approval_until_finish"] = true
    wizard_template["required"] = true
    CustomWizard::Template.save(wizard_template, skip_jobs: true)
  end

  # NOTE: User#after_commit fires :user_created automatically when Fabricate runs.
  # The plugin's handler is registered globally, so creating a user via Fabricate
  # is enough to exercise the hook — no manual DiscourseEvent.trigger needed.

  describe "on :user_created" do
    it "temp-approves the user and sets the marker when delay_approval is configured" do
      user = Fabricate(:user, approved: false)
      user.reload

      expect(user.approved).to eq(true)
      expect(user.approved_by_id).to eq(Discourse.system_user.id)
      expect(user.approved_at).to be_present
      expect(user.custom_fields["delayed_approval_wizard_id"]).to eq("super_mega_fun_wizard")
    end

    it "does not temp-approve staff signups" do
      user = Fabricate(:user, approved: false, admin: true)
      user.reload

      expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
      expect(user.admin).to eq(true)
    end

    it "does not modify users who are already approved" do
      user = Fabricate(:user, approved: true)
      user.reload

      expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
    end

    it "does nothing when must_approve_users and invite_only are both off" do
      SiteSetting.must_approve_users = false
      SiteSetting.invite_only = false

      user = Fabricate(:user, approved: false)
      user.reload

      expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
    end

    it "does nothing when delay_approval_until_finish is disabled on the wizard" do
      wizard_template["delay_approval_until_finish"] = false
      CustomWizard::Template.save(wizard_template, skip_jobs: true)

      user = Fabricate(:user, approved: false)
      user.reload

      expect(user.approved).to eq(false)
      expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
    end

    it "does nothing when no after_signup wizard exists at all" do
      CustomWizard::Template.remove("super_mega_fun_wizard")

      user = Fabricate(:user, approved: false)
      user.reload

      expect(user.approved).to eq(false)
      expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
    end
  end

  describe "on :user_unstaged" do
    it "temp-approves the user and sets the marker" do
      # Create the user as already-approved so the :user_created auto-fire from
      # Fabricate is a no-op (handler returns early on `user.approved?`).
      # Then revert approval and explicitly trigger the unstage event.
      user = Fabricate(:user, approved: true, staged: true)

      user.update_columns(approved: false, staged: false)
      DiscourseEvent.trigger(:user_unstaged, user)
      user.reload

      expect(user.approved).to eq(true)
      expect(user.custom_fields["delayed_approval_wizard_id"]).to eq("super_mega_fun_wizard")
    end
  end
end

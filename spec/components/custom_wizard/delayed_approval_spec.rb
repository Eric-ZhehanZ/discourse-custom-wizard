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

describe "reviewable submission link" do
  fab!(:user) { Fabricate(:user, approved: true) }
  let(:template) { get_wizard_fixture("wizard") }

  before do
    SiteSetting.must_approve_users = true
    template["after_signup"] = true
    template["delay_approval_until_finish"] = true
    template["required"] = true
    CustomWizard::Template.save(template, skip_jobs: true)

    # Create a wizard submission for the user
    wizard = CustomWizard::Wizard.create("super_mega_fun_wizard", user)
    submission = CustomWizard::Submission.new(wizard, { "step_1_field_1" => "answer" })
    submission.save
  end

  # NOTE: ReviewableUser.needs_review! triggers :reviewable_created via
  # `after_commit on: :create` (see Reviewable model). No manual DiscourseEvent
  # trigger needed.

  it "appends wizard_submission_url to the reviewable payload" do
    reviewable =
      ReviewableUser.needs_review!(
        target: user,
        created_by: Discourse.system_user,
        reviewable_by_moderator: true,
        payload: {
          username: user.username,
        },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to eq(
      "/admin/wizards/submissions/super_mega_fun_wizard",
    )
  end

  it "does nothing for users without a wizard submission" do
    # The before block creates a wizard submission for `user`. Use a fresh user
    # who has no wizard submissions of their own.
    other_user = Fabricate(:user, approved: true)
    other_user.custom_fields.delete("delayed_approval_wizard_id")
    other_user.save_custom_fields(true)

    reviewable =
      ReviewableUser.needs_review!(
        target: other_user,
        created_by: Discourse.system_user,
        reviewable_by_moderator: true,
        payload: {
          username: other_user.username,
        },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to be_blank
  end

  it "uses the delayed_approval_wizard_id marker when present" do
    # Explicitly exercise the marker branch: if a reviewable is somehow created
    # while the user is still in delayed-approval lockdown, we use the marker
    # directly rather than the fallback.
    user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    user.save_custom_fields(true)

    reviewable =
      ReviewableUser.needs_review!(
        target: user,
        created_by: Discourse.system_user,
        reviewable_by_moderator: true,
        payload: {
          username: user.username,
        },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to eq(
      "/admin/wizards/submissions/super_mega_fun_wizard",
    )
  end

  it "ignores non-user reviewables" do
    # The listener must early-return for reviewable types that aren't ReviewableUser.
    # We use a ReviewableQueuedPost as a representative non-user reviewable type.
    category = Fabricate(:category)
    topic = Fabricate(:topic, category: category)
    post = Fabricate(:post, topic: topic)

    reviewable =
      ReviewableQueuedPost.needs_review!(
        target: post,
        created_by: Discourse.system_user,
        reviewable_by_moderator: true,
        payload: {
          raw: "test post",
        },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to be_blank
  end
end

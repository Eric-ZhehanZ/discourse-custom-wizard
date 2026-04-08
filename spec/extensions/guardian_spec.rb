# frozen_string_literal: true

describe CustomWizardGuardian do
  fab!(:topic)
  fab!(:post)
  fab!(:other_user, :user)

  let(:user) { Fabricate(:user, approved: true) }
  let(:guardian) { Guardian.new(user) }

  context "when user is in delayed-approval window" do
    before do
      user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
      user.save_custom_fields(true)
    end

    it "blocks can_see_topic?" do
      expect(guardian.can_see_topic?(topic)).to eq(false)
    end

    it "blocks can_see_post?" do
      expect(guardian.can_see_post?(post)).to eq(false)
    end

    it "blocks can_create_post? on a topic" do
      expect(guardian.can_create_post?(topic)).to eq(false)
    end

    it "blocks can_send_private_message? to another user" do
      expect(guardian.can_send_private_message?(other_user)).to eq(false)
    end

    it "does NOT override can_edit_user? at the Guardian layer" do
      # Intentional: core Discourse routes several user-scoped READ endpoints
      # (e.g. `UsersController#private_message_topic_tracking_state`) through
      # `guardian.ensure_can_edit!(user)`. Overriding `can_edit_user?` here
      # would 403 those reads and surface the generic "not permitted to view"
      # popup on every wizard page load. Profile writes are gated at the
      # controller level instead (see CustomWizardUsersController#update).
      expect(guardian.can_edit_user?(user)).to eq(true)
    end

    context "when the user is staff" do
      before { user.update!(admin: true) }

      it "does not block can_see_topic?" do
        expect(guardian.can_see_topic?(topic)).to eq(true)
      end

      it "does not block can_create_post?" do
        expect(guardian.can_create_post?(topic)).to eq(true)
      end
    end
  end

  context "when user is not in the delayed-approval window" do
    it "does not block can_see_topic?" do
      expect(guardian.can_see_topic?(topic)).to eq(true)
    end
  end

  context "with anonymous guardian" do
    let(:guardian) { Guardian.new }

    it "falls through to core for can_see_topic?" do
      expect(guardian.can_see_topic?(topic)).to eq(true)
    end
  end
end

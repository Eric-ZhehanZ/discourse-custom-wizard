# frozen_string_literal: true

describe CustomWizardUsersController, type: :request do
  let(:template) { get_wizard_fixture("wizard") }

  before { @controller = UsersController.new }

  it "redirects a user to wizard after sign up if after signup is enabled" do
    template["after_signup"] = true
    CustomWizard::Template.save(template, skip_jobs: true)
    sign_in(Fabricate(:user))
    get "/u/account-created"
    expect(response).to redirect_to("/w/super-mega-fun-wizard")
  end

  describe "delayed-approval lockdown" do
    fab!(:locked_user, :user)

    before do
      template["after_signup"] = true
      template["delay_approval_until_finish"] = true
      template["required"] = true
      CustomWizard::Template.save(template)
      locked_user.update!(approved: true)
      locked_user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
      locked_user.save_custom_fields(true)
      sign_in(locked_user)
    end

    it "blocks PUT /u/:username.json (profile update) with 403" do
      put "/u/#{locked_user.username}.json", params: { bio_raw: "hello" }
      expect(response.status).to eq(403)
      body = JSON.parse(response.body)
      expect(body["errors"]).to include(/not permitted/)
    end

    it "allows GET /u/:username/private-message-topic-tracking-state" do
      # Regression test: before the controller-level fix, an over-broad
      # `can_edit_user?` Guardian override caused this read endpoint to
      # return 403 on every wizard page load.
      get "/u/#{locked_user.username}/private-message-topic-tracking-state", as: :json
      expect(response.status).to eq(200)
    end

    it "allows other user-scoped reads that go through ensure_can_edit!" do
      # Same root cause: any user-scoped data read that checks
      # `can_edit?(user)` should keep working during the lockdown window.
      get "/u/#{locked_user.username}.json"
      expect(response.status).to eq(200)
    end

    it "does not block profile updates for staff users who happen to hold the marker" do
      locked_user.update!(admin: true)
      put "/u/#{locked_user.username}.json", params: { bio_raw: "hello" }
      expect(response.status).to eq(200)
    end
  end
end

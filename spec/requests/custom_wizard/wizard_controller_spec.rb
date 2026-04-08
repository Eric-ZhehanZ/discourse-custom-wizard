# frozen_string_literal: true

describe CustomWizard::WizardController do
  fab!(:user) do
    Fabricate(:user, username: "angus", email: "angus@email.com", trust_level: TrustLevel[3])
  end
  let(:wizard_template) { get_wizard_fixture("wizard") }
  let(:permitted_json) { get_wizard_fixture("wizard/permitted") }

  before do
    CustomWizard::Template.save(wizard_template, skip_jobs: true)
    @template = CustomWizard::Template.find("super_mega_fun_wizard")
  end

  context "plugin disabled" do
    before { SiteSetting.custom_wizard_enabled = false }

    it "redirects to root" do
      get "/w/super-mega-fun-wizard", xhr: true
      expect(response).to redirect_to("/")
    end
  end

  it "returns wizard" do
    get "/w/super-mega-fun-wizard.json"
    expect(response.parsed_body["id"]).to eq("super_mega_fun_wizard")
  end

  it "returns missing message if no wizard exists" do
    get "/w/super-mega-fun-wizards.json"
    expect(response.parsed_body["error"]).to eq("We couldn't find a wizard at that address.")
  end

  context "with user" do
    before { sign_in(user) }

    context "when user skips" do
      it "skips a wizard if user is allowed to skip" do
        put "/w/super-mega-fun-wizard/skip.json"
        expect(response.status).to eq(200)
      end

      it "lets user skip if user cant access wizard" do
        enable_subscription("standard")
        @template["permitted"] = permitted_json["permitted"]
        CustomWizard::Template.save(@template, skip_jobs: true)
        put "/w/super-mega-fun-wizard/skip.json"
        expect(response.status).to eq(200)
      end

      it "returns a no skip message if user is not allowed to skip" do
        enable_subscription("standard")
        @template["required"] = "true"
        CustomWizard::Template.save(@template)
        put "/w/super-mega-fun-wizard/skip.json"
        expect(response.parsed_body["error"]).to eq("Wizard can't be skipped")
      end

      it "skip response contains a redirect_to if in users submissions" do
        @wizard = CustomWizard::Wizard.create(@template["id"], user)
        CustomWizard::Submission.new(@wizard, redirect_to: "/t/2").save
        put "/w/super-mega-fun-wizard/skip.json"
        expect(response.parsed_body["redirect_to"]).to eq("/t/2")
      end

      it "deletes the users redirect_to_wizard if present" do
        user.custom_fields["redirect_to_wizard"] = @template["id"]
        user.save_custom_fields(true)
        @wizard = CustomWizard::Wizard.create(@template["id"], user)
        put "/w/super-mega-fun-wizard/skip.json"
        expect(response.status).to eq(200)
        expect(user.reload.redirect_to_wizard).to eq(nil)
      end

      it "deletes the submission if user has filled up some data" do
        @wizard = CustomWizard::Wizard.create(@template["id"], user)
        CustomWizard::Submission.new(@wizard, step_1_field_1: "Hello World").save
        current_submission = @wizard.current_submission
        put "/w/super-mega-fun-wizard/skip.json"
        submissions = CustomWizard::Submission.list(@wizard).submissions

        expect(submissions.any? { |submission| submission.id == current_submission.id }).to eq(
          false,
        )
      end

      it "starts from the first step if user visits after skipping the wizard" do
        put "/w/super-mega-fun-wizard/steps/step_1.json",
            params: {
              fields: {
                step_1_field_1: "Text input",
              },
            }
        put "/w/super-mega-fun-wizard/skip.json"
        get "/w/super-mega-fun-wizard.json"

        expect(response.parsed_body["start"]).to eq("step_1")
      end
    end
  end

  context "delayed-approval user" do
    before do
      @template["after_signup"] = true
      @template["delay_approval_until_finish"] = true
      @template["required"] = true
      CustomWizard::Template.save(@template)
      user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
      user.save_custom_fields(true)
      sign_in(user)
    end

    it "rejects skip with 403" do
      put "/w/super_mega_fun_wizard/skip.json"
      expect(response.status).to eq(403)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq(I18n.t("wizard.delayed_approval.cannot_skip"))
    end

    it "does not reject skip when marker is for a different wizard" do
      # Marker points at a different wizard id; the guard must NOT fire and
      # the request should fall through to normal skip logic.
      user.custom_fields["delayed_approval_wizard_id"] = "some_other_wizard"
      user.save_custom_fields(true)

      put "/w/super_mega_fun_wizard/skip.json"
      expect(response.status).not_to eq(403)
    end
  end
end

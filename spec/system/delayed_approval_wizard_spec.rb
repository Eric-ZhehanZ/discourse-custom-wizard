# frozen_string_literal: true

describe "Delayed approval wizard flow" do
  fab!(:admin)

  let(:wizard_template) do
    {
      "id" => "verify_wizard",
      "name" => "Verify Wizard",
      "after_signup" => true,
      "delay_approval_until_finish" => true,
      "required" => true,
      "save_submissions" => true,
      "steps" => [
        {
          "id" => "step_1",
          "title" => "Tell us about yourself",
          "fields" => [
            {
              "id" => "step_1_field_1",
              "label" => "Your reason for joining",
              "type" => "text",
              "required" => true,
            },
          ],
        },
      ],
    }
  end

  before do
    SiteSetting.custom_wizard_enabled = true
    SiteSetting.must_approve_users = true
    CustomWizard::Template.save(wizard_template, skip_jobs: true)
  end

  it "temp-approves on signup and locks the user to the wizard URL" do
    user = Fabricate(:user, approved: false, active: true)
    DiscourseEvent.trigger(:user_created, user)
    user.reload

    expect(user.approved).to eq(true)
    expect(user.custom_fields["delayed_approval_wizard_id"]).to eq("verify_wizard")

    sign_in(user)

    visit "/categories"
    expect(page).to have_current_path(%r{/w/verify-wizard})
  end

  it "does not lock out admins who somehow have the marker" do
    admin.custom_fields["delayed_approval_wizard_id"] = "verify_wizard"
    admin.save_custom_fields(true)

    sign_in(admin)
    visit "/latest"

    expect(page).to have_current_path("/latest")
  end
end

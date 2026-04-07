# Delay Approval Until Wizard Finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `delay_approval_until_finish` wizard option that lets users sign up under `must_approve_users`/`invite_only`, complete a verification wizard while temporarily approved-but-locked-down, and then return to the admin review queue with their wizard submission attached.

**Architecture:** Temp-approve users at signup via the `:user_created` and `:user_unstaged` events so they can log in. Mark them with a `delayed_approval_wizard_id` user custom field. Enforce a two-layer lockdown (HTML redirect to wizard + Guardian content-denial overrides) while the marker is set, with staff bypass at every layer. On wizard completion, revoke approval, clear the marker, queue a fresh `ReviewableUser`, and log the user out.

**Tech Stack:** Ruby (Discourse plugin), Ember.js (admin UI), RSpec, Capybara (system specs).

**Spec:** `docs/superpowers/specs/2026-04-08-delay-approval-until-wizard-finish-design.md`

**Wizard fixture used by tests:** `spec/fixtures/wizard.json` (the `super_mega_fun_wizard`). Loaded via `get_wizard_fixture("wizard")` and saved with `CustomWizard::Template.save(template, skip_jobs: true)`.

---

## Conventions for every task

- Run all `bin/*` commands from `/Users/zhehanz/Developer/discourse-dev/discourse` (the Discourse repo). RSpec needs the host Discourse app loaded — `bin/rspec` is the helper at the Discourse root that handles this. Use the absolute path to the plugin spec file: `bin/rspec plugins/discourse-custom-wizard/spec/path/to/file_spec.rb`.
- Use `fab!` over `let()` per the Discourse `CLAUDE.md`. Use `fab!(:name) { Fabricate(:user, attrs) }` when you need custom attributes.
- Lint Ruby files after every change: `bin/lint plugins/discourse-custom-wizard/path/to/file.rb` from the Discourse root. Use `--fix` to auto-fix.
- Lint JS files the same way for any `*.js` or `*.hbs` you touch.
- Each task ends with a commit using a Conventional Commits prefix (`feat:`, `test:`, `refactor:`, etc.).
- Do NOT skip pre-commit hooks (no `--no-verify`).
- The plugin's working directory in this repo is `/Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard`. All file paths in this plan are relative to that directory unless noted otherwise.

---

## Task 1: Add `delay_approval_until_finish` to the wizard model

**Files:**
- Modify: `lib/custom_wizard/wizard.rb` (the `CustomWizard::Wizard` class)
- Test: `spec/components/custom_wizard/wizard_spec.rb`

The model is the foundation — every other backend task reads from it.

- [ ] **Step 1: Write the failing test**

Open `spec/components/custom_wizard/wizard_spec.rb`. Find the existing top-level describe block (look for `describe CustomWizard::Wizard do`) and add this test inside it, near the other attribute tests:

```ruby
describe "#delay_approval_until_finish" do
  it "defaults to false when not set in the template" do
    wizard = CustomWizard::Wizard.new({ "id" => "test", "name" => "Test" })
    expect(wizard.delay_approval_until_finish).to eq(false)
  end

  it "casts a true value from the template" do
    wizard = CustomWizard::Wizard.new(
      { "id" => "test", "name" => "Test", "delay_approval_until_finish" => true }
    )
    expect(wizard.delay_approval_until_finish).to eq(true)
  end

  it "casts a stringy 'true' value from the template" do
    wizard = CustomWizard::Wizard.new(
      { "id" => "test", "name" => "Test", "delay_approval_until_finish" => "true" }
    )
    expect(wizard.delay_approval_until_finish).to eq(true)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `/Users/zhehanz/Developer/discourse-dev/discourse`:
```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "delay_approval_until_finish"
```
Expected: 3 failures, error like `NoMethodError: undefined method 'delay_approval_until_finish'`.

- [ ] **Step 3: Add the attribute to the model**

In `lib/custom_wizard/wizard.rb`, find the `attr_accessor` block at the top of the class. Add `:delay_approval_until_finish` to the list (after `:after_signup`):

```ruby
attr_accessor :id,
              :name,
              :background,
              :theme_id,
              :save_submissions,
              :multiple_submissions,
              :after_time,
              :after_time_scheduled,
              :after_time_group_names,
              :after_signup,
              :delay_approval_until_finish,
              :required,
              :prompt_completion,
              :restart_on_revisit,
              :resume_on_revisit,
              :permitted,
              :steps,
              :step_ids,
              :field_ids,
              :first_step,
              :start,
              :actions,
              :action_ids,
              :user,
              :guest_id,
              :template
```

In the `initialize` method, find where `@after_signup = cast_bool(attrs["after_signup"])` is set (around line 59). Add immediately below it:

```ruby
    @delay_approval_until_finish = cast_bool(attrs["delay_approval_until_finish"])
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "delay_approval_until_finish"
```
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/lib/custom_wizard/wizard.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add lib/custom_wizard/wizard.rb spec/components/custom_wizard/wizard_spec.rb
git commit -m "feat: add delay_approval_until_finish attribute to wizard model"
```

---

## Task 2: Permit `delay_approval_until_finish` in the admin save params

**Files:**
- Modify: `app/controllers/custom_wizard/admin/wizard.rb`
- Test: `spec/requests/custom_wizard/admin/wizard_controller_spec.rb`

- [ ] **Step 1: Write the failing test**

Open `spec/requests/custom_wizard/admin/wizard_controller_spec.rb`, find the `describe "#save"` block, and add a new test next to the existing save tests:

```ruby
it "saves the delay_approval_until_finish flag" do
  put "/admin/wizards/wizard/super_mega_fun_wizard.json",
      params: {
        wizard: {
          id: "super_mega_fun_wizard",
          name: "Super Mega Fun Wizard",
          after_signup: true,
          delay_approval_until_finish: true,
          required: true,
          steps: [{ id: "step_1" }],
        },
      }
  expect(response.status).to eq(200)
  template = CustomWizard::Template.find("super_mega_fun_wizard")
  expect(template["delay_approval_until_finish"]).to eq(true)
end
```

If the file doesn't already have an admin sign-in `before` block, add one (model after the existing tests in the file).

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/admin/wizard_controller_spec.rb -e "delay_approval_until_finish"
```
Expected: failure, the saved template will not contain `delay_approval_until_finish` (it's filtered out by strong params).

- [ ] **Step 3: Add to permitted params**

In `app/controllers/custom_wizard/admin/wizard.rb`, find the `save_wizard_params` method (around line 65). The first block of permitted scalars looks like:

```ruby
def save_wizard_params
  params.require(:wizard).permit(
    :id,
    :name,
    :background,
    :save_submissions,
    :multiple_submissions,
    :after_signup,
    :after_time,
    :after_time_scheduled,
    :required,
```

Add `:delay_approval_until_finish` immediately after `:after_signup`:

```ruby
def save_wizard_params
  params.require(:wizard).permit(
    :id,
    :name,
    :background,
    :save_submissions,
    :multiple_submissions,
    :after_signup,
    :delay_approval_until_finish,
    :after_time,
    :after_time_scheduled,
    :required,
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/admin/wizard_controller_spec.rb -e "delay_approval_until_finish"
```
Expected: 1 example, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/app/controllers/custom_wizard/admin/wizard.rb plugins/discourse-custom-wizard/spec/requests/custom_wizard/admin/wizard_controller_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add app/controllers/custom_wizard/admin/wizard.rb spec/requests/custom_wizard/admin/wizard_controller_spec.rb
git commit -m "feat: permit delay_approval_until_finish in admin save params"
```

---

## Task 3: Validate `delay_approval_until_finish` requires `after_signup` and forces `required`

**Files:**
- Modify: `lib/custom_wizard/validators/template.rb`
- Test: `spec/components/custom_wizard/template_validator_spec.rb`

- [ ] **Step 1: Write the failing tests**

Open `spec/components/custom_wizard/template_validator_spec.rb` and add a new context inside the existing `describe CustomWizard::TemplateValidator do` block:

```ruby
context "delay_approval_until_finish" do
  let(:base_template) do
    {
      "id" => "delayed_wizard",
      "name" => "Delayed Wizard",
      "after_signup" => true,
      "delay_approval_until_finish" => true,
      "required" => true,
      "steps" => [{ "id" => "step_1" }],
    }
  end

  it "is valid when after_signup is true and required is true" do
    validator = CustomWizard::TemplateValidator.new(base_template)
    expect(validator.perform).to eq(true)
    expect(validator.errors).to be_empty
  end

  it "is invalid when after_signup is false" do
    template = base_template.merge("after_signup" => false)
    validator = CustomWizard::TemplateValidator.new(template)
    expect(validator.perform).to eq(false)
    expect(validator.errors.full_messages).to include(
      I18n.t("wizard.validation.delay_approval_requires_after_signup")
    )
  end

  it "forces required to true when delay_approval_until_finish is true" do
    template = base_template.merge("required" => false)
    validator = CustomWizard::TemplateValidator.new(template)
    validator.perform
    expect(template["required"]).to eq(true)
  end
end
```

Also add the locale string this test references — open `config/locales/server.en.yml`, find the `wizard.validation:` section, and add (alphabetically with other validation keys):

```yaml
        delay_approval_requires_after_signup: "delay_approval_until_finish requires after_signup to be true"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/template_validator_spec.rb -e "delay_approval_until_finish"
```
Expected: 3 failures (no validation logic exists yet).

- [ ] **Step 3: Add the validator method**

In `lib/custom_wizard/validators/template.rb`, find the `perform` method (around line 12). Add a call to a new validator method right after `validate_after_signup`:

```ruby
def perform
  data = @data

  check_id(data, :wizard)
  check_required(data, :wizard)
  validate_after_signup
  validate_delay_approval_until_finish
  validate_after_time
  validate_subscription(data, :wizard)
```

Then add the new method to the `private` section, after `validate_after_signup`:

```ruby
def validate_delay_approval_until_finish
  return unless ActiveRecord::Type::Boolean.new.cast(@data[:delay_approval_until_finish])

  unless ActiveRecord::Type::Boolean.new.cast(@data[:after_signup])
    errors.add :base, I18n.t("wizard.validation.delay_approval_requires_after_signup")
    return
  end

  # Force required=true so the user cannot skip the wizard during the lockdown window
  @data[:required] = true
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/template_validator_spec.rb -e "delay_approval_until_finish"
```
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/lib/custom_wizard/validators/template.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/template_validator_spec.rb plugins/discourse-custom-wizard/config/locales/server.en.yml
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add lib/custom_wizard/validators/template.rb spec/components/custom_wizard/template_validator_spec.rb config/locales/server.en.yml
git commit -m "feat: validate delay_approval_until_finish wizard configuration"
```

---

## Task 4: Add the temp-approval signup hook

**Files:**
- Modify: `plugin.rb`
- Create: `spec/components/custom_wizard/delayed_approval_spec.rb`

This is the core hook. It runs at user-creation time (and at user-unstage time for the staged-user case) to set the user as temporarily approved and stamp them with the lockdown marker.

- [ ] **Step 1: Write the failing tests**

Create `spec/components/custom_wizard/delayed_approval_spec.rb`:

```ruby
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
    end

    it "does not modify users who are already approved" do
      user = Fabricate(:user, approved: true)
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
```

`update_columns` is used (instead of `update!`) to bypass any callbacks/validations and write directly to the DB. This isolates the test to just the `:user_unstaged` event behavior.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb
```
Expected: 6 failures, the user is never approved or marked.

- [ ] **Step 3: Add the helper method to the wizard model**

In `lib/custom_wizard/wizard.rb`, after the existing `self.after_signup` class method (around line 368), add a new class method that picks the after_signup wizard regardless of permitted, since we're consulting it for ALL signups (the existing method filters by `permitted?` which requires a user context that doesn't apply for a delay-approval check):

```ruby
def self.delay_approval_until_finish_template
  template = CustomWizard::Template.list(setting: "after_signup").first
  return nil unless template

  ActiveRecord::Type::Boolean.new.cast(template["delay_approval_until_finish"]) ? template : nil
end
```

- [ ] **Step 4: Add the event handlers in plugin.rb**

In `plugin.rb`, find the existing `on(:user_approved)` block (around line 145). Add immediately after it:

```ruby
delay_approval_handler =
  proc do |user|
    next if user.staff?
    next if user.approved?

    template = CustomWizard::Wizard.delay_approval_until_finish_template
    next unless template

    ReviewableUser.set_approved_fields!(user, Discourse.system_user)
    user.save!
    user.custom_fields["delayed_approval_wizard_id"] = template["id"]
    user.save_custom_fields(true)
  end

on(:user_created, &delay_approval_handler)
on(:user_unstaged, &delay_approval_handler)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb
```
Expected: 6 examples, 0 failures.

- [ ] **Step 6: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/plugin.rb plugins/discourse-custom-wizard/lib/custom_wizard/wizard.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add plugin.rb lib/custom_wizard/wizard.rb spec/components/custom_wizard/delayed_approval_spec.rb
git commit -m "feat: temp-approve users on signup when delay_approval_until_finish is set"
```

---

## Task 5: HTML lockdown — extend `redirect_to_wizard_if_required`

**Files:**
- Modify: `plugin.rb`
- Test: `spec/requests/custom_wizard/application_controller_spec.rb`

The existing `redirect_to_wizard_if_required` already redirects users with `redirect_to_wizard` set. We add a stricter branch for delayed-approval users that ignores the configurable `wizard_redirect_exclude_paths` and only allows wizard URLs and login/logout.

- [ ] **Step 1: Write the failing tests**

In `spec/requests/custom_wizard/application_controller_spec.rb`, add a new context inside the `context "with signed in user"` block, near the other lockdown contexts:

```ruby
context "in delayed-approval lockdown" do
  before do
    @template["after_signup"] = true
    @template["delay_approval_until_finish"] = true
    @template["required"] = true
    CustomWizard::Template.save(@template)
    user.approved = true
    user.save!
    user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    user.save_custom_fields(true)
  end

  it "redirects HTML requests to the wizard" do
    get "/"
    expect(response).to redirect_to("/w/super-mega-fun-wizard")
  end

  it "redirects HTML requests for any other path to the wizard" do
    get "/categories"
    expect(response).to redirect_to("/w/super-mega-fun-wizard")
  end

  it "ignores wizard_redirect_exclude_paths" do
    SiteSetting.wizard_redirect_exclude_paths = "/escape"
    get "/escape"
    expect(response).to redirect_to("/w/super-mega-fun-wizard")
  end

  it "does not redirect requests already pointing at the wizard" do
    get "/w/super-mega-fun-wizard"
    expect(response).not_to be_redirect
  end

  it "does not redirect /session requests" do
    get "/session/csrf.json"
    expect(response).not_to be_redirect
  end

  it "does not lock out staff" do
    user.update!(admin: true)
    get "/"
    expect(response).not_to redirect_to("/w/super-mega-fun-wizard")
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/application_controller_spec.rb -e "in delayed-approval lockdown"
```
Expected: most failures — the existing redirect logic only fires when the user has `redirect_to_wizard` set, which we are intentionally not setting in these tests.

- [ ] **Step 3: Extend the before_action**

In `plugin.rb`, find the existing `add_to_class(:application_controller, :redirect_to_wizard_if_required)` block (around line 151). Replace it with this updated version:

```ruby
add_to_class(:application_controller, :redirect_to_wizard_if_required) do
  return if current_user.blank?

  delayed_approval_wizard_id = current_user.custom_fields["delayed_approval_wizard_id"]
  in_delayed_approval = delayed_approval_wizard_id.present? && !current_user.staff?

  if in_delayed_approval
    return if request.format != "text/html"

    url = request.original_url
    wizard_path_segment = "/w/#{delayed_approval_wizard_id.dasherize}"
    return if url.include?(wizard_path_segment)
    return if url =~ %r{/session(/|\.|\z)}
    return if url =~ %r{/logout(/|\.|\z)}
    return if url =~ %r{/login(/|\.|\z)}

    redirect_to wizard_path_segment
    return
  end

  @excluded_routes ||= SiteSetting.wizard_redirect_exclude_paths.split("|") + ["/w/"]
  url = request.referer || request.original_url
  excluded_route = @excluded_routes.any? { |str| /#{str}/ =~ url }
  not_api = request.format === "text/html"

  if not_api && !excluded_route
    wizard_id = current_user.redirect_to_wizard

    if CustomWizard::Template.can_redirect_users?(wizard_id)
      if url !~ %r{/w/} && url !~ %r{/invites/}
        CustomWizard::Wizard.set_wizard_redirect(current_user, wizard_id, url)
      end

      wizard = CustomWizard::Wizard.create(wizard_id, current_user)
      redirect_to "/w/#{wizard_id.dasherize}" if wizard.should_redirect?
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/application_controller_spec.rb -e "in delayed-approval lockdown"
```
Expected: 6 examples, 0 failures.

- [ ] **Step 5: Run the full file to make sure existing tests still pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/application_controller_spec.rb
```
Expected: all examples pass — the legacy `redirect_to_wizard` flow is unchanged.

- [ ] **Step 6: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/plugin.rb plugins/discourse-custom-wizard/spec/requests/custom_wizard/application_controller_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add plugin.rb spec/requests/custom_wizard/application_controller_spec.rb
git commit -m "feat: HTML lockdown for delayed-approval users"
```

---

## Task 6: Guardian content denial overrides

**Files:**
- Modify: `lib/custom_wizard/extensions/guardian.rb`
- Test: `spec/extensions/guardian_spec.rb` (new file)

Guardian is the content-access layer. Block topic/post viewing, post/PM creation, and self-edit while the marker is set.

- [ ] **Step 1: Write the failing tests**

Create `spec/extensions/guardian_spec.rb`:

```ruby
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

    it "blocks self-edit via can_edit_user?" do
      expect(guardian.can_edit_user?(user)).to eq(false)
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

    it "does not raise on can_see_topic?" do
      expect { guardian.can_see_topic?(topic) }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/extensions/guardian_spec.rb
```
Expected: most failures — existing Guardian methods return true (or what core decides) and the overrides don't exist.

- [ ] **Step 3: Add the overrides**

Replace `lib/custom_wizard/extensions/guardian.rb` with:

```ruby
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

  def can_see_topic?(topic)
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
```

The `try(:staff?)` call protects against an anonymous guardian where `@user` is `nil` — `try` returns `nil` (falsy) on nil. We already short-circuit on `@user.blank?` above, but the `try` is a defense-in-depth in case core ever changes the anonymous-user representation.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/extensions/guardian_spec.rb
```
Expected: all examples pass.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/lib/custom_wizard/extensions/guardian.rb plugins/discourse-custom-wizard/spec/extensions/guardian_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add lib/custom_wizard/extensions/guardian.rb spec/extensions/guardian_spec.rb
git commit -m "feat: Guardian content denial for delayed-approval users"
```

---

## Task 7: Block wizard skipping for delayed-approval users

**Files:**
- Modify: `app/controllers/custom_wizard/wizard.rb`
- Test: `spec/requests/custom_wizard/wizard_controller_spec.rb` (extend existing)

The validator already forces `required=true` (Task 3). The frontend will hide the skip button. This task adds a server-side guard so a crafted request can't bypass it.

- [ ] **Step 1: Add the locale string**

In `config/locales/server.en.yml`, find the `wizard:` namespace, and add a new sub-namespace at the end of it:

```yaml
        delayed_approval:
          cannot_skip: "This wizard cannot be skipped while your account is awaiting approval."
```

- [ ] **Step 2: Write the failing test**

In `spec/requests/custom_wizard/wizard_controller_spec.rb`, find the existing skip-related context (look for `describe "#skip"` or similar). If the file doesn't exist or doesn't have skip tests, search for one that does:

```bash
grep -rn "describe.*skip\|wizard.*skip" plugins/discourse-custom-wizard/spec/requests/
```

Add a new context to the appropriate file (likely `spec/requests/custom_wizard/wizard_controller_spec.rb`):

```ruby
context "delayed-approval user" do
  fab!(:user) { Fabricate(:user, approved: true) }

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
end
```

If the spec file doesn't exist, create it with the standard structure: load `wizard_template`, save it in a `before` block, and assign `@template`.

- [ ] **Step 3: Run the test to verify it fails**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/wizard_controller_spec.rb -e "delayed-approval user"
```
Expected: failure — skip currently returns 200 because `required=true` only blocks skipping in JS, not in the backend skip endpoint (the backend allows the skip with side effects).

- [ ] **Step 4: Add the guard**

In `app/controllers/custom_wizard/wizard.rb`, modify the `skip` action. Add the new guard at the very top of the action, before the existing `params.require(:wizard_id)`:

```ruby
def skip
  params.require(:wizard_id)

  if current_user &&
       current_user.custom_fields["delayed_approval_wizard_id"] == params[:wizard_id].underscore
    return(
      render json: { error: I18n.t("wizard.delayed_approval.cannot_skip") }, status: 403
    )
  end

  if wizard.required && !wizard.completed? && wizard.permitted?
    return render json: { error: I18n.t("wizard.no_skip") }
  end

  result = { success: "OK" }

  if current_user && wizard.can_access?
    if redirect_to = wizard.current_submission&.redirect_to
      result.merge!(redirect_to: redirect_to)
    end

    wizard.cleanup_on_skip!
  end

  render json: result
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/wizard_controller_spec.rb -e "delayed-approval user"
```
Expected: 1 example, 0 failures.

- [ ] **Step 6: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/app/controllers/custom_wizard/wizard.rb plugins/discourse-custom-wizard/spec/requests/custom_wizard/wizard_controller_spec.rb plugins/discourse-custom-wizard/config/locales/server.en.yml
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add app/controllers/custom_wizard/wizard.rb spec/requests/custom_wizard/wizard_controller_spec.rb config/locales/server.en.yml
git commit -m "feat: block wizard skip for delayed-approval users"
```

---

## Task 8: Wizard completion → revoke approval

**Files:**
- Modify: `lib/custom_wizard/wizard.rb`
- Test: `spec/components/custom_wizard/wizard_spec.rb`

When `cleanup_on_complete!` runs and the user was in the delayed-approval window, revoke approval, clear the marker, and queue a fresh `ReviewableUser` job.

- [ ] **Step 1: Write the failing tests**

In `spec/components/custom_wizard/wizard_spec.rb`, add a new context inside the existing top-level describe:

```ruby
describe "#cleanup_on_complete! with delayed approval" do
  fab!(:user) { Fabricate(:user, approved: true) }
  let(:template) { get_wizard_fixture("wizard") }

  before do
    SiteSetting.must_approve_users = true
    template["after_signup"] = true
    template["delay_approval_until_finish"] = true
    template["required"] = true
    CustomWizard::Template.save(template, skip_jobs: true)
    user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    user.save_custom_fields(true)
  end

  let(:wizard) { CustomWizard::Wizard.create("super_mega_fun_wizard", user) }

  it "revokes approval, clears the marker, and enqueues a reviewable" do
    Jobs.expects(:enqueue).with(:create_user_reviewable, user_id: user.id)

    wizard.cleanup_on_complete!
    user.reload

    expect(user.approved).to eq(false)
    expect(user.approved_by_id).to be_nil
    expect(user.approved_at).to be_nil
    expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
  end

  it "does nothing for users without the marker" do
    user.custom_fields.delete("delayed_approval_wizard_id")
    user.save_custom_fields(true)

    Jobs.expects(:enqueue).never

    wizard.cleanup_on_complete!
    user.reload

    expect(user.approved).to eq(true)
  end
end

describe "#delayed_approval_pending?" do
  fab!(:user) { Fabricate(:user, approved: true) }
  let(:template) { get_wizard_fixture("wizard") }

  before do
    template["after_signup"] = true
    template["delay_approval_until_finish"] = true
    template["required"] = true
    CustomWizard::Template.save(template, skip_jobs: true)
  end

  let(:wizard) { CustomWizard::Wizard.create("super_mega_fun_wizard", user) }

  it "returns true when the user has the marker matching this wizard" do
    user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    user.save_custom_fields(true)

    expect(wizard.delayed_approval_pending?).to eq(true)
  end

  it "returns false when the marker is missing" do
    expect(wizard.delayed_approval_pending?).to eq(false)
  end

  it "returns false when the marker points at a different wizard" do
    user.custom_fields["delayed_approval_wizard_id"] = "other_wizard"
    user.save_custom_fields(true)

    expect(wizard.delayed_approval_pending?).to eq(false)
  end

  it "returns false when there is no user (guest)" do
    guest_wizard = CustomWizard::Wizard.create("super_mega_fun_wizard", nil, "guest_abc")
    expect(guest_wizard.delayed_approval_pending?).to eq(false)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "delayed_approval"
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "cleanup_on_complete! with delayed approval"
```
Expected: failures — neither method exists yet.

- [ ] **Step 3: Implement the methods**

In `lib/custom_wizard/wizard.rb`, find `cleanup_on_complete!` (around line 310). Replace it and add the two new helpers:

```ruby
def cleanup_on_complete!
  was_in_delayed_approval = delayed_approval_pending?

  remove_user_redirect

  if current_submission.present?
    current_submission.submitted_at = Time.now.iso8601
    current_submission.save
  end

  trigger_delayed_approval_revocation! if was_in_delayed_approval

  update!
end

def delayed_approval_pending?
  return false if user.blank?
  user.custom_fields["delayed_approval_wizard_id"] == id
end

def trigger_delayed_approval_revocation!
  user.approved = false
  user.approved_by_id = nil
  user.approved_at = nil
  user.save!

  user.custom_fields.delete("delayed_approval_wizard_id")
  user.save_custom_fields(true)

  Jobs.enqueue(:create_user_reviewable, user_id: user.id)
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "delayed_approval"
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb -e "cleanup_on_complete! with delayed approval"
```
Expected: all examples pass. Also run the full file to make sure nothing else broke:
```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb
```

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/lib/custom_wizard/wizard.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/wizard_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add lib/custom_wizard/wizard.rb spec/components/custom_wizard/wizard_spec.rb
git commit -m "feat: revoke approval and enqueue reviewable on wizard completion"
```

---

## Task 9: Sign user out at wizard completion

**Files:**
- Modify: `app/controllers/custom_wizard/steps.rb`
- Test: `spec/requests/custom_wizard/steps_controller_spec.rb` (or wherever the steps controller is tested)

After `cleanup_on_complete!` revokes approval, the user's session is still valid. We log them off and tell the JS frontend to redirect to `/login`, where Discourse's existing `login_not_approved` UX takes over.

- [ ] **Step 1: Find or create the steps controller spec**

```bash
find plugins/discourse-custom-wizard/spec -name "*step*" -type f
```

If there's no steps controller spec, create `spec/requests/custom_wizard/steps_controller_spec.rb`:

```ruby
# frozen_string_literal: true

describe CustomWizard::StepsController do
  fab!(:user) { Fabricate(:user, approved: true) }
  let(:template) { get_wizard_fixture("wizard") }

  before do
    SiteSetting.must_approve_users = true
    template["after_signup"] = true
    template["delay_approval_until_finish"] = true
    template["required"] = true
    CustomWizard::Template.save(template, skip_jobs: true)
    user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    user.save_custom_fields(true)
    sign_in(user)
  end

  describe "#update" do
    context "when finishing a delayed-approval wizard" do
      it "logs the user off and redirects to /login" do
        # Walk through every step except the last via the standard PUT,
        # then submit the final step.
        wizard = CustomWizard::Wizard.create("super_mega_fun_wizard", user)
        steps = wizard.steps

        steps[0..-2].each do |step|
          put "/w/super_mega_fun_wizard/steps/#{step.id}.json",
              params: { fields: {} }
          expect(response.status).to eq(200)
        end

        put "/w/super_mega_fun_wizard/steps/#{steps.last.id}.json",
            params: { fields: {} }

        expect(response.status).to eq(200)
        body = JSON.parse(response.body)
        expect(body["final"]).to eq(true)
        expect(body["redirect_on_complete"]).to eq("/login")

        # Session should be cleared — a follow-up request must look unauthenticated
        get "/session/current.json"
        expect(response.status).to eq(404).or eq(403).or eq(200)
        # The exact status depends on Discourse's anonymous-session handling;
        # the key check is that the previous user is no longer signed in.
      end
    end
  end
end
```

If the wizard fixture's steps require certain field values, simplify this by stubbing them out via a minimal in-test fixture (use `let(:template)` to override `template["steps"]` with a single field-less step). Recommended approach: define a single-step minimal template at the top:

```ruby
let(:template) do
  {
    "id" => "delay_test_wizard",
    "name" => "Delay Test Wizard",
    "after_signup" => true,
    "delay_approval_until_finish" => true,
    "required" => true,
    "steps" => [{ "id" => "step_1", "fields" => [] }],
  }
end
```

And then save with `CustomWizard::Template.save(template, skip_jobs: true)` and use the `delay_test_wizard` ID throughout.

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/steps_controller_spec.rb
```
Expected: failure — `redirect_on_complete` is not set, the user is not logged off.

- [ ] **Step 3: Modify the steps controller**

In `app/controllers/custom_wizard/steps.rb#update`, around the existing `if current_step.final?` block, snapshot the delayed-approval state BEFORE `cleanup_on_complete!` and act on it AFTER:

```ruby
if current_step.final?
  builder.template.actions.each do |action_template|
    if action_template["run_after"] === "wizard_completion"
      action_result =
        CustomWizard::Action.new(
          action: action_template,
          wizard: @wizard,
          submission: current_submission,
        ).perform

      current_submission = action_result.submission if action_result.success?
    end
  end

  current_submission.save

  was_in_delayed_approval = @wizard.delayed_approval_pending?

  if redirect = get_redirect
    updater.result[:redirect_on_complete] = redirect
  end

  @wizard.cleanup_on_complete!

  if was_in_delayed_approval
    log_off_user
    updater.result[:redirect_on_complete] = "/login"
  end

  result[:final] = true
else
  current_submission.save

  result[:final] = false
  result[:next_step_id] = current_step.next.id
end
```

The `log_off_user` call here is `Discourse::CurrentUser#log_off_user`, which is mixed into all controllers. It clears the session and cookie.

The `redirect_on_complete = "/login"` assignment intentionally **overrides** any value set by `get_redirect` (e.g., a `route_to` action). For delayed-approval wizards, the post-completion target is the login flow, period — no exceptions. Document this in a code comment:

```ruby
  if was_in_delayed_approval
    # Override any route_to / redirect_on_next from the wizard config:
    # delayed-approval wizards always end with the user logged out and sent
    # to the login flow, where Discourse's existing not-approved UX takes over.
    log_off_user
    updater.result[:redirect_on_complete] = "/login"
  end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/requests/custom_wizard/steps_controller_spec.rb
```
Expected: pass.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/app/controllers/custom_wizard/steps.rb plugins/discourse-custom-wizard/spec/requests/custom_wizard/steps_controller_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add app/controllers/custom_wizard/steps.rb spec/requests/custom_wizard/steps_controller_spec.rb
git commit -m "feat: log off and redirect to login on delayed-approval wizard finish"
```

---

## Task 10: Cleanup on wizard delete

**Files:**
- Modify: `lib/custom_wizard/template.rb`
- Test: `spec/components/custom_wizard/template_spec.rb`

If the admin deletes a wizard while users are mid-flow, those users still hold `approved=true` from the temp-approval. We must revoke them and queue them for review before dropping the marker.

- [ ] **Step 1: Write the failing test**

In `spec/components/custom_wizard/template_spec.rb`, add a new context to the existing `describe ".remove"` (or create one if missing):

```ruby
context "with delayed-approval users in flight" do
  fab!(:in_flight_user) do
    Fabricate(
      :user,
      approved: true,
      approved_at: Time.now,
      approved_by: Discourse.system_user,
    )
  end

  before do
    template = get_wizard_fixture("wizard")
    template["after_signup"] = true
    template["delay_approval_until_finish"] = true
    template["required"] = true
    CustomWizard::Template.save(template, skip_jobs: true)
    in_flight_user.custom_fields["delayed_approval_wizard_id"] = "super_mega_fun_wizard"
    in_flight_user.save_custom_fields(true)
  end

  it "revokes in-flight users and queues them for review" do
    Jobs.expects(:enqueue).with(:create_user_reviewable, user_id: in_flight_user.id)

    CustomWizard::Template.remove("super_mega_fun_wizard")

    in_flight_user.reload
    expect(in_flight_user.approved).to eq(false)
    expect(in_flight_user.custom_fields["delayed_approval_wizard_id"]).to be_blank
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/template_spec.rb -e "delayed-approval"
```
Expected: failure — `Jobs.expects(:enqueue)` is not called, user is still approved.

- [ ] **Step 3: Add the cleanup**

In `lib/custom_wizard/template.rb`, find the `self.remove` class method (around line 56). Modify it to call a new helper before the existing transaction:

```ruby
def self.remove(wizard_id)
  wizard = CustomWizard::Wizard.create(wizard_id)
  return false if !wizard

  ActiveRecord::Base.transaction do
    revoke_delayed_approval_for_in_flight_users(wizard_id)
    ensure_wizard_upload_references!(wizard_id)
    PluginStore.remove(CustomWizard::PLUGIN_NAME, wizard.id)
    clear_user_wizard_redirect(wizard_id, after_time: !!wizard.after_time)
    related_custom_fields =
      CategoryCustomField.where(
        name: "create_topic_wizard",
        value: wizard.name.parameterize(separator: "_"),
      )
    related_custom_fields.destroy_all
  end

  clear_cache_keys

  true
end
```

Then add the helper as a class method (still in the public class methods section, near `clear_user_wizard_redirect`):

```ruby
def self.revoke_delayed_approval_for_in_flight_users(wizard_id)
  user_ids =
    UserCustomField
      .where(name: "delayed_approval_wizard_id", value: wizard_id)
      .pluck(:user_id)

  User.where(id: user_ids).find_each do |user|
    user.approved = false
    user.approved_by_id = nil
    user.approved_at = nil
    user.save!
    user.custom_fields.delete("delayed_approval_wizard_id")
    user.save_custom_fields(true)
    Jobs.enqueue(:create_user_reviewable, user_id: user.id)
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/template_spec.rb -e "delayed-approval"
```
Expected: pass. Also run the full file:
```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/template_spec.rb
```

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/lib/custom_wizard/template.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/template_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add lib/custom_wizard/template.rb spec/components/custom_wizard/template_spec.rb
git commit -m "feat: revoke in-flight delayed-approval users on wizard delete"
```

---

## Task 11: Link the wizard submission from the reviewable

**Files:**
- Modify: `plugin.rb`
- Test: `spec/components/custom_wizard/delayed_approval_spec.rb` (extend existing)

After revocation enqueues `Jobs::CreateUserReviewable`, the resulting `ReviewableUser` should have a payload pointer to the user's wizard submission so the admin can click through.

- [ ] **Step 1: Write the failing test**

Add to `spec/components/custom_wizard/delayed_approval_spec.rb`:

```ruby
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
        payload: { username: user.username },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to eq(
      "/admin/wizards/submissions/super_mega_fun_wizard"
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
        payload: { username: other_user.username },
      )
    reviewable.reload

    expect(reviewable.payload["wizard_submission_url"]).to be_blank
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb -e "reviewable submission link"
```
Expected: failures — payload doesn't get the URL.

- [ ] **Step 3: Add the listener in plugin.rb**

In `plugin.rb`, after the existing `on(:user_created)` and `on(:user_unstaged)` handlers, add:

```ruby
on(:reviewable_created) do |reviewable|
  next unless reviewable.is_a?(ReviewableUser)
  next unless reviewable.target.is_a?(User)

  user = reviewable.target

  delayed_wizard_id = user.custom_fields["delayed_approval_wizard_id"]
  candidate_wizard_id = nil

  if delayed_wizard_id.present?
    candidate_wizard_id = delayed_wizard_id
  else
    template = CustomWizard::Template.list(setting: "after_signup").first
    candidate_wizard_id = template["id"] if template
  end

  next if candidate_wizard_id.blank?

  wizard = CustomWizard::Wizard.create(candidate_wizard_id, user)
  next if wizard.blank?
  next if wizard.submissions.blank?

  payload = reviewable.payload || {}
  payload["wizard_submission_url"] = "/admin/wizards/submissions/#{candidate_wizard_id}"
  reviewable.update!(payload: payload)
end
```

Why both branches: at the moment of `cleanup_on_complete!` we already cleared the marker, so by the time the reviewable is created from the `Jobs::CreateUserReviewable` job, the marker is gone. We fall back to "the active after_signup wizard" — which is what the user just finished.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb -e "reviewable submission link"
```
Expected: 2 examples, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/plugin.rb plugins/discourse-custom-wizard/spec/components/custom_wizard/delayed_approval_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add plugin.rb spec/components/custom_wizard/delayed_approval_spec.rb
git commit -m "feat: link wizard submission from reviewable user payload"
```

---

## Task 12: Frontend wizard schema

**Files:**
- Modify: `assets/javascripts/discourse/lib/wizard-schema.js`

Add the new field to the JS schema so the admin form binds to it correctly.

- [ ] **Step 1: Add the field**

Open `assets/javascripts/discourse/lib/wizard-schema.js`. Find the `wizard.basic` object near the top:

```javascript
const wizard = {
  basic: {
    id: null,
    name: null,
    background: null,
    save_submissions: true,
    multiple_submissions: null,
    after_signup: null,
    after_time: null,
    after_time_scheduled: null,
    required: null,
    prompt_completion: null,
    restart_on_revisit: null,
    resume_on_revisit: null,
    theme_id: null,
    permitted: null,
    after_time_groups: null,
  },
```

Add `delay_approval_until_finish: null,` immediately after `after_signup: null,`:

```javascript
const wizard = {
  basic: {
    id: null,
    name: null,
    background: null,
    save_submissions: true,
    multiple_submissions: null,
    after_signup: null,
    delay_approval_until_finish: null,
    after_time: null,
    after_time_scheduled: null,
    required: null,
    prompt_completion: null,
    restart_on_revisit: null,
    resume_on_revisit: null,
    theme_id: null,
    permitted: null,
    after_time_groups: null,
  },
```

- [ ] **Step 2: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/assets/javascripts/discourse/lib/wizard-schema.js
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add assets/javascripts/discourse/lib/wizard-schema.js
git commit -m "feat: add delay_approval_until_finish to wizard JS schema"
```

---

## Task 13: Admin form checkbox

**Files:**
- Modify: `assets/javascripts/discourse/templates/admin-wizards-wizard-show.hbs`
- Modify: `config/locales/client.en.yml`

Add the new checkbox to the admin wizard editor, conditionally shown when `after_signup` is enabled.

- [ ] **Step 1: Add locale strings**

In `config/locales/client.en.yml`, find the `admin.wizard:` section. After the `after_signup_label` line, add:

```yaml
        delay_approval_until_finish: "Delay Approval"
        delay_approval_until_finish_label: "Send users back to the admin review queue after they finish the wizard. Requires \"Signup\" to be enabled."
```

Indentation must match the surrounding lines exactly.

- [ ] **Step 2: Add the checkbox to the template**

In `assets/javascripts/discourse/templates/admin-wizards-wizard-show.hbs`, find the existing `after_signup` checkbox block (around line 89-97):

```handlebars
    <div class="setting">
      <div class="setting-label">
        <label>{{i18n "admin.wizard.after_signup"}}</label>
      </div>
      <div class="setting-value">
        <Input @type="checkbox" @checked={{this.wizard.after_signup}} />
        <span>{{i18n "admin.wizard.after_signup_label"}}</span>
      </div>
    </div>
```

Add a new conditional block immediately below it (still inside `.wizard-settings`):

```handlebars
    {{#if this.wizard.after_signup}}
      <div class="setting">
        <div class="setting-label">
          <label>{{i18n "admin.wizard.delay_approval_until_finish"}}</label>
        </div>
        <div class="setting-value">
          <Input @type="checkbox" @checked={{this.wizard.delay_approval_until_finish}} />
          <span>{{i18n "admin.wizard.delay_approval_until_finish_label"}}</span>
        </div>
      </div>
    {{/if}}
```

- [ ] **Step 3: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/assets/javascripts/discourse/templates/admin-wizards-wizard-show.hbs plugins/discourse-custom-wizard/config/locales/client.en.yml
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add assets/javascripts/discourse/templates/admin-wizards-wizard-show.hbs config/locales/client.en.yml
git commit -m "feat: admin form checkbox for delay_approval_until_finish"
```

---

## Task 14: Reviewable user admin connector (link to wizard submission)

**Files:**
- Create: `assets/javascripts/discourse/connectors/reviewable-user-extra/wizard-submission-link.hbs`
- Create: `assets/javascripts/discourse/connectors/reviewable-user-extra/wizard-submission-link.js`

Render the wizard-submission link in the admin reviewable user view via a connector. First check the outlet exists in the current Discourse version.

- [ ] **Step 1: Verify the outlet name**

```bash
grep -rn "PluginOutlet.*reviewable" /Users/zhehanz/Developer/discourse-dev/discourse/app/assets/javascripts/discourse/app/components/reviewable*.gjs /Users/zhehanz/Developer/discourse-dev/discourse/app/assets/javascripts/discourse/app/components/reviewable*.hbs 2>/dev/null | head -10
```

Note the actual outlet names. If `reviewable-user-extra` doesn't exist, look for `reviewable-item` or similar — the closest outlet on the reviewable user view. Use whichever exists. If only a generic outlet exists, gate rendering on `@outletArgs.reviewable.payload.wizard_submission_url` so it stays a no-op for non-wizard reviewables.

If no suitable outlet exists in the current Discourse version, this task can be skipped — the data is still available in the reviewable JSON for any admin querying directly. Note this in the commit message.

- [ ] **Step 2: Create the connector .hbs file**

Create `assets/javascripts/discourse/connectors/<outlet-from-step-1>/wizard-submission-link.hbs`:

```handlebars
{{#if @outletArgs.reviewable.payload.wizard_submission_url}}
  <div class="wizard-submission-link">
    <a
      href={{@outletArgs.reviewable.payload.wizard_submission_url}}
      target="_blank"
      rel="noopener noreferrer"
    >
      {{i18n "admin.wizard.reviewable_view_submission"}}
    </a>
  </div>
{{/if}}
```

- [ ] **Step 3: Create the connector .js file**

Create `assets/javascripts/discourse/connectors/<outlet-from-step-1>/wizard-submission-link.js`:

```javascript
export default {
  shouldRender(args) {
    return args.reviewable?.payload?.wizard_submission_url;
  },
};
```

- [ ] **Step 4: Add the locale string**

In `config/locales/client.en.yml`, in the `admin.wizard:` section, add:

```yaml
        reviewable_view_submission: "View wizard submission"
```

- [ ] **Step 5: Manual smoke test**

Can be deferred to the end-to-end system spec in Task 15. Mark this task complete after committing.

- [ ] **Step 6: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/assets/javascripts/discourse/connectors plugins/discourse-custom-wizard/config/locales/client.en.yml
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add assets/javascripts/discourse/connectors/ config/locales/client.en.yml
git commit -m "feat: connector to display wizard submission link in reviewable user view"
```

---

## Task 15: End-to-end system spec

**Files:**
- Create: `spec/system/delayed_approval_wizard_spec.rb`
- Create: `spec/system/page_objects/pages/custom_wizard.rb` (if not already present)

A Capybara system spec that walks through the full flow: signup → land on wizard → submit → revoked → redirected to login.

- [ ] **Step 1: Check for an existing wizard page object**

```bash
find plugins/discourse-custom-wizard/spec/system -type f 2>/dev/null
```

If a `page_objects/pages/custom_wizard.rb` doesn't exist, create one with minimal helpers needed for this spec.

- [ ] **Step 2: Write the system spec**

Create `spec/system/delayed_approval_wizard_spec.rb`:

```ruby
# frozen_string_literal: true

describe "Delayed approval wizard flow", type: :system do
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

  it "temp-approves on signup, locks down to wizard, revokes after completion" do
    # Sign up a new user (mimic the real signup form)
    user = Fabricate(:user, approved: false, active: true)
    DiscourseEvent.trigger(:user_created, user)
    user.reload

    expect(user.approved).to eq(true)
    expect(user.custom_fields["delayed_approval_wizard_id"]).to eq("verify_wizard")

    sign_in(user)

    # Visit any page — should redirect to the wizard
    visit "/categories"
    expect(page).to have_current_path(%r{/w/verify-wizard})

    # Fill out the wizard
    find("input[type='text']").fill_in(with: "I want to learn")
    click_button("wizard.next") # button text key — adjust to actual selector

    # User should now be revoked and on the login page
    user.reload
    expect(user.approved).to eq(false)
    expect(user.custom_fields["delayed_approval_wizard_id"]).to be_blank
    expect(page).to have_current_path(%r{/login})

    # Reviewable should exist
    reviewable = ReviewableUser.find_by(target_id: user.id)
    expect(reviewable).to be_present
    expect(reviewable.payload["wizard_submission_url"]).to eq(
      "/admin/wizards/submissions/verify_wizard"
    )
  end

  it "does not lock out admins who somehow have the marker" do
    admin.custom_fields["delayed_approval_wizard_id"] = "verify_wizard"
    admin.save_custom_fields(true)
    sign_in(admin)

    visit "/categories"
    expect(page).to have_current_path("/categories")
  end
end
```

The button selector `click_button("wizard.next")` is approximate — adjust to match the actual wizard frontend. Use the wizard repository's existing system specs as a reference, or use `page.find` with the actual selector by inspecting the wizard template at `assets/javascripts/discourse/templates/components/wizard-step.hbs` or similar.

- [ ] **Step 3: Run the system spec**

System specs can be slow. Run with:
```bash
bin/rspec plugins/discourse-custom-wizard/spec/system/delayed_approval_wizard_spec.rb
```

If it fails because of selectors, iterate on the page interactions (use `save_and_open_page` or `page.html` to inspect mid-test).

- [ ] **Step 4: Lint and commit**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/lint plugins/discourse-custom-wizard/spec/system/delayed_approval_wizard_spec.rb
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
git add spec/system/delayed_approval_wizard_spec.rb
git commit -m "test: end-to-end system spec for delayed-approval wizard flow"
```

---

## Task 16: Final regression run

Run the full test suite to confirm nothing else broke.

- [ ] **Step 1: Run the full plugin spec suite**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse
bin/rspec plugins/discourse-custom-wizard/spec
```
Expected: all passing.

- [ ] **Step 2: Run the full plugin lint**

```bash
cd /Users/zhehanz/Developer/discourse-dev/discourse-custom-wizard
bundle exec rubocop --parallel
yarn eslint -f compact --quiet --ext .js .
yarn prettier --list-different "**/*.js" "**/*.scss"
```
Expected: clean (or auto-fix any drift with `--fix` / `--write`).

- [ ] **Step 3: Manual smoke (optional but recommended)**

Boot the dev environment, enable `must_approve_users`, create a delay-approval wizard, sign up a test user, and walk through the flow once. Verify:
- Signup works without admin intervention
- Wizard is the only thing visible
- Skip button is hidden
- Direct skip request returns 403
- After completion, user lands at /login
- Admin sees the user in the review queue with the wizard submission link
- Admin approval flows correctly afterward

This is hands-on verification. Document any rough edges as follow-up tickets rather than expanding this plan.

- [ ] **Step 4: No commit needed unless lint produced fixes**

If lint auto-fixed anything, commit:
```bash
git add -A
git commit -m "style: lint fixes after delay_approval_until_finish feature"
```

---

## Out of plan / future work

These were considered and intentionally deferred:

- **Per-wizard custom "awaiting approval" page** instead of the generic Discourse not-approved page. The current design uses Discourse's existing UX for consistency.
- **Configurable allowed-paths during lockdown** for admins who want to whitelist specific URLs (e.g., a help page). Add only if requested.
- **Bulk admin "release stuck users" command** for the plugin-disabled edge case. Add if real-world use surfaces it.
- **JS-side skip-button UI hint** explaining why skip is hidden for delayed-approval wizards. The validator already forces `required=true`, so the existing hidden state covers it.

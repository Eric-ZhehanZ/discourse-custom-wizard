# frozen_string_literal: true
module Jobs
  # Self-chaining reminder for users who have skipped (or are inside the
  # soft-skip window of) a forced wizard. Each run sends one reminder DM
  # then re-enqueues itself one interval later — "recurring until done".
  # It is self-terminating: it stops as soon as the user completes the
  # wizard, enters the review pipeline, the feature is turned off, or the
  # hard deadline passes (sending a single final notice in that last case).
  #
  # Because every stop condition is re-checked live, a stale job left over
  # from a config change simply no-ops on its next run.
  class CustomWizardSkipReminder < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.custom_wizard_enabled

      user = User.find_by(id: args[:user_id])
      return if user.blank?

      wizard = CustomWizard::Wizard.create(args[:wizard_id], user)
      return if wizard.blank?

      policy = CustomWizard::SkipPolicy

      # Chain was stopped (completion/approval/disable cleared the flag).
      return unless policy.reminding?(user, wizard)

      # No longer applicable: completed, submitted for review, approved,
      # or the admin turned the feature off. Stop and tidy up.
      unless policy.applicable?(user, wizard)
        policy.clear_state!(user, wizard) if wizard.completed?
        policy.stop_reminders!(user, wizard)
        return
      end

      # Deadline reached: one final "you must verify now" notice, then stop.
      if policy.deadline_passed?(user, wizard)
        policy.send_final_notice!(user, wizard)
        policy.stop_reminders!(user, wizard)
        return
      end

      # Admin disabled reminders mid-flight (the wizard is still active):
      # stop the chain; a later skip/redirect will reschedule it.
      unless wizard.skip_reminder_enabled
        policy.stop_reminders!(user, wizard)
        return
      end

      policy.send_reminder!(user, wizard)

      Jobs.enqueue_at(
        Time.now.utc + policy.reminder_interval(wizard).hours,
        :custom_wizard_skip_reminder,
        user_id: user.id,
        wizard_id: wizard.id,
      )
    end
  end
end

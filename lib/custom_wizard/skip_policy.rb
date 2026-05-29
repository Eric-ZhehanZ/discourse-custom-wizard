# frozen_string_literal: true

# Soft-skip policy for forced wizards.
#
# When a forced wizard (after_signup / restrict_to_approved /
# delay_approval_until_finish) opts in with `skip_enabled`, this turns
# the all-or-nothing gate into a ramp so an event can absorb mass
# registration without forcing everyone to upload ID at sign-up:
#
#   1. Grace      — for `skip_defer_hours` after registration the wizard
#                   never appears; full access.
#   2. Soft window — the redirect ("popup") reappears, but the user may
#                   "Skip for now" up to `skip_max` times. A skip snoozes
#                   the redirect for `snooze_hours` (= the reminder
#                   interval) and grants full forum access meanwhile.
#                   Recurring DMs nudge them.
#   3. Hard lock  — once skips are exhausted OR the effective deadline
#                   passes, skipping is refused, the redirect is
#                   permanent and Guardian lockdown re-engages. This is
#                   the unchanged pre-existing behavior; we only defer
#                   *when* it kicks in. The deadline is the security
#                   backstop.
#
# Effective deadline = earliest of (registration + skip_deadline_hours)
# and the absolute skip_event_deadline; the event cutoff is the dominant
# ceiling and always wins once reached. Unset values are treated as +∞.
#
# Every decision is computed live from `user.custom_fields` + the wizard
# template, so the deadline backstop holds even if the reminder job
# never runs. Per-user state follows the existing `wizard_*_<id>`
# custom-field convention (stored as strings, read with `.to_i`).
module CustomWizard
  class SkipPolicy
    DEFAULT_SNOOZE_HOURS = 24

    class << self
      # ---- custom field keys (per wizard id) -------------------------
      def used_field(wizard_id)
        "wizard_skips_used_#{wizard_id}"
      end

      def snooze_field(wizard_id)
        "wizard_skip_snooze_until_#{wizard_id}"
      end

      def reminding_field(wizard_id)
        "wizard_skip_reminding_#{wizard_id}"
      end

      def deadline_notified_field(wizard_id)
        "wizard_skip_deadline_notified_#{wizard_id}"
      end

      # ---- feature gate ----------------------------------------------
      def enabled?(wizard)
        !!(wizard && wizard.user && wizard.respond_to?(:skip_enabled) && wizard.skip_enabled)
      end

      # The soft window only governs the pre-submission phase. Once the
      # user has submitted (entered the review pipeline) or been
      # approved, the existing review/approval lockdown owns their
      # access and we must NOT keep granting soft-window access or
      # nagging them. Denied users are hard-redirected by the review
      # flow and likewise fall out of the soft window.
      def pre_submission?(user, wizard)
        wid = wizard.id
        return false if user.custom_fields["wizard_approved_#{wid}"].present?
        state = user.custom_fields["wizard_review_state_#{wid}"].to_s
        return false if state.present? && state != "none"
        return false if wizard.completed?
        true
      end

      # A user is only subject to a wizard's soft-skip rules when that
      # wizard is actually gating them — its redirect target or their
      # delayed-approval lock. set_user_redirect only sets
      # redirect_to_wizard when can_access? is true, so exempt /
      # non-permitted users never match and therefore can't skip, accrue
      # skip state, or trigger reminders for a wizard they aren't subject to.
      def gating_this_user?(user, wizard)
        wid = wizard.id.to_s
        user.custom_fields["redirect_to_wizard"].to_s == wid ||
          user.custom_fields["delayed_approval_wizard_id"].to_s == wid
      end

      def applicable?(user, wizard)
        enabled?(wizard) && gating_this_user?(user, wizard) && pre_submission?(user, wizard)
      end

      # ---- time helpers ----------------------------------------------
      def now
        Time.now.utc
      end

      # A bare datetime-local value ("2026-06-01T18:00") carries no zone;
      # interpret it as UTC explicitly so the absolute event cutoff fires
      # at the same wall-clock instant regardless of the server process
      # timezone. A value that already carries an offset keeps its zone.
      def parse_time(value)
        return nil if value.blank?
        parsed = ActiveSupport::TimeZone["UTC"].parse(value.to_s)
        parsed&.utc
      rescue ArgumentError, TypeError
        nil
      end

      def registered_at(user)
        user.created_at&.utc
      end

      # ---- grace / deadline ------------------------------------------
      def defer_grace_active?(user, wizard)
        hours = wizard.skip_defer_hours.to_i
        return false if hours <= 0
        reg = registered_at(user)
        return false if reg.blank?
        now < (reg + hours.hours)
      end

      def relative_deadline(user, wizard)
        hours = wizard.skip_deadline_hours.to_i
        return nil if hours <= 0
        reg = registered_at(user)
        return nil if reg.blank?
        reg + hours.hours
      end

      def event_deadline(wizard)
        parse_time(wizard.skip_event_deadline)
      end

      # Earliest of the two configured deadlines (event cutoff is an
      # absolute ceiling). nil when neither is configured.
      def deadline_for(user, wizard)
        [relative_deadline(user, wizard), event_deadline(wizard)].compact.min
      end

      # Fail-closed: a skip-enabled wizard with no resolvable deadline is
      # treated as already past its deadline, so malformed or legacy data
      # (whose save-time mandatory-deadline validation was somehow
      # bypassed) locks users rather than granting a permanent bypass. A
      # correctly-saved wizard always has a deadline, so this only bites
      # malformed data.
      def deadline_passed?(user, wizard)
        dl = deadline_for(user, wizard)
        return true if dl.blank?
        now >= dl
      end

      # ---- skip accounting -------------------------------------------
      def skips_used(user, wizard)
        user.custom_fields[used_field(wizard.id)].to_i
      end

      def skips_remaining(user, wizard)
        [wizard.skip_max.to_i - skips_used(user, wizard), 0].max
      end

      def snoozed?(user, wizard)
        until_at = parse_time(user.custom_fields[snooze_field(wizard.id)])
        until_at.present? && now < until_at
      end

      # ---- the three decision predicates -----------------------------

      # The user may actively dismiss the wizard right now.
      def can_skip?(user, wizard)
        applicable?(user, wizard) && !deadline_passed?(user, wizard) &&
          skips_remaining(user, wizard) > 0
      end

      # Suppress the forced redirect (server 302 + client SPA + serializer)
      # — within the grace window or while a skip snooze is active.
      def suppress_redirect?(user, wizard)
        return false unless applicable?(user, wizard)
        return false if deadline_passed?(user, wizard)
        defer_grace_active?(user, wizard) || snoozed?(user, wizard)
      end

      # Grant full forum access (Guardian does not lock) exactly when the
      # forced redirect is suppressed — during the grace window or an
      # active skip snooze. Deliberately NOT keyed on merely having skips
      # left: a post-grace user who hasn't skipped yet stays locked AND is
      # redirected to the wizard until they explicitly click "Skip for
      # now" (which sets the snooze). Keeping the content gate and the
      # redirect in lockstep stops a JSON/API request from reading content
      # the HTML redirect would have blocked.
      def in_soft_window?(user, wizard)
        suppress_redirect?(user, wizard)
      end

      # Re-prompt / snooze cadence after a skip. Reuses the reminder
      # interval so the nudge DM and the re-appearance line up; falls
      # back to a sane default when reminders are off or misconfigured.
      def snooze_hours(wizard)
        hours = wizard.skip_reminder_interval_hours.to_i
        hours > 0 ? hours : DEFAULT_SNOOZE_HOURS
      end

      def reminder_interval(wizard)
        snooze_hours(wizard)
      end

      # ---- mutations -------------------------------------------------
      # Record one skip atomically. Concurrent skip requests each load
      # their own user row, so a plain read-modify-write could let two
      # requests both read N and both write N+1, over-granting past
      # skip_max. We take a row lock, re-read the persisted count, and
      # re-validate the cap so the loser is refused. Returns false when the
      # skip could not be granted (cap reached / deadline passed mid-flight).
      def record_skip!(user, wizard)
        granted =
          user.with_lock do
            next false unless can_skip?(user, wizard)
            user.custom_fields[used_field(wizard.id)] = skips_used(user, wizard) + 1
            user.custom_fields[snooze_field(wizard.id)] = (now + snooze_hours(wizard).hours).iso8601
            user.save_custom_fields(true)
            true
          end
        ensure_reminder_scheduled!(user, wizard) if granted
        granted
      end

      # Schedule the first reminder of a self-chaining series, once.
      def ensure_reminder_scheduled!(user, wizard)
        return unless applicable?(user, wizard)
        return unless wizard.skip_reminder_enabled
        return if user.custom_fields[reminding_field(wizard.id)].present?

        user.custom_fields[reminding_field(wizard.id)] = true
        user.save_custom_fields(true)
        Jobs.enqueue_at(
          now + reminder_interval(wizard).hours,
          :custom_wizard_skip_reminder,
          user_id: user.id,
          wizard_id: wizard.id,
        )
      end

      def reminding?(user, wizard)
        user.custom_fields[reminding_field(wizard.id)].present?
      end

      def stop_reminders!(user, wizard)
        return if user.custom_fields[reminding_field(wizard.id)].blank?
        user.custom_fields.delete(reminding_field(wizard.id))
        user.save_custom_fields(true)
      end

      # Full reset — called when the wizard is completed/approved so a
      # re-enrollment (multiple_submissions / re-verification) starts clean.
      def clear_state!(user, wizard)
        wid = wizard.respond_to?(:id) ? wizard.id : wizard
        deleted = false
        [used_field(wid), snooze_field(wid), reminding_field(wid), deadline_notified_field(wid)].each do |f|
          if user.custom_fields[f].present?
            user.custom_fields.delete(f)
            deleted = true
          end
        end
        user.save_custom_fields(true) if deleted
      end

      # ---- reminder DMs ----------------------------------------------
      # Locale-neutral, numeric format (no English month names), shown in
      # the user's own timezone when they have one set, else UTC. %Z
      # appends the zone abbreviation so the instant is unambiguous.
      def format_deadline(time, user = nil)
        return I18n.t("system_messages.custom_wizard_skip_reminder.no_deadline") if time.blank?
        tz = user&.user_option&.timezone
        local = tz.present? ? (time.in_time_zone(tz) rescue time.utc) : time.utc
        local.strftime("%Y-%m-%d %H:%M %Z")
      end

      def interpolate(template, vars)
        vars.reduce(template.to_s.dup) do |str, (key, value)|
          str.gsub("%{#{key}}", value.to_s)
        end
      end

      def reminder_vars(user, wizard)
        {
          username: user.username,
          wizard_name: wizard.name,
          wizard_url: "/w/#{wizard.id.dasherize}",
          remaining_skips: skips_remaining(user, wizard),
          deadline: format_deadline(deadline_for(user, wizard), user),
        }
      end

      def send_reminder!(user, wizard)
        body =
          wizard.skip_reminder_text.presence ||
            I18n.t("system_messages.custom_wizard_skip_reminder.text_body_template")
        title = I18n.t("system_messages.custom_wizard_skip_reminder.title")
        deliver_dm!(user, title, interpolate(body, reminder_vars(user, wizard)))
      end

      # One-shot "deadline reached, you must verify now" notice.
      def send_final_notice!(user, wizard)
        return if user.custom_fields[deadline_notified_field(wizard.id)].present?

        vars = reminder_vars(user, wizard)
        title = I18n.t("system_messages.custom_wizard_skip_deadline_reached.title")
        body = I18n.t("system_messages.custom_wizard_skip_deadline_reached.text_body_template")
        delivered = deliver_dm!(user, title, interpolate(body, vars))

        if delivered
          user.custom_fields[deadline_notified_field(wizard.id)] = true
          user.save_custom_fields(true)
        end
      end

      # Send a private message from the system user, then create the
      # notification by hand — a brand-new PM recipient isn't watching
      # the topic, so PostAlerter would otherwise leave it silent (no
      # bell, no email). Mirrors ReviewableCustomWizardSubmission#notify_user.
      def deliver_dm!(user, title, raw)
        return false if user.blank? || raw.blank? || title.blank?

        creator =
          PostCreator.new(
            Discourse.system_user,
            title: title,
            raw: raw,
            archetype: Archetype.private_message,
            target_usernames: user.username,
            skip_validations: true,
          )
        post = creator.create

        if creator.errors.present?
          Rails.logger.warn(
            "custom_wizard: skip reminder PM failed for user #{user.id}: #{creator.errors.full_messages.join(" ")}",
          )
          return false
        end

        if post && post.topic
          PostAlerter.new.create_notification(user, Notification.types[:private_message], post)
        end
        true
      rescue StandardError => e
        Rails.logger.warn(
          "custom_wizard: skip reminder PM raised for user #{user&.id}: #{e.class}: #{e.message}",
        )
        false
      end
    end
  end
end

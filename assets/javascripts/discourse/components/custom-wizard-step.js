import Component from "@ember/component";
import { alias, not, or } from "@ember/object/computed";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import $ from "jquery";
import { cook } from "discourse/lib/text";
import getUrl from "discourse-common/lib/get-url";
import discourseLater from "discourse-common/lib/later";
import discourseComputed, { observes } from "discourse-common/utils/decorators";
import CustomWizard, {
  updateCachedWizard,
} from "discourse/plugins/discourse-custom-wizard/discourse/models/custom-wizard";
import { wizardComposerEdtiorEventPrefix } from "./custom-wizard-composer-editor";

const uploadStartedEventKeys = ["upload-started"];
const uploadEndedEventKeys = [
  "upload-success",
  "upload-error",
  "upload-cancelled",
  "uploads-cancelled",
  "uploads-aborted",
  "all-uploads-complete",
];

export default Component.extend({
  classNameBindings: [":wizard-step", "step.id"],
  saving: null,
  wizardState: service(),

  init() {
    this._super(...arguments);
    this.set("stylingDropdown", {});
  },

  didReceiveAttrs() {
    this._super(...arguments);

    // Publish the active wizard + step so the parent custom-wizard template
    // can render the progress bar in the wizard footer, next to the logo.
    this.wizardState.setActive(this.wizard, this.step);

    cook(this.step.translatedTitle).then((cookedTitle) => {
      this.set("cookedTitle", cookedTitle);
    });
    cook(this.step.translatedDescription).then((cookedDescription) => {
      this.set("cookedDescription", cookedDescription);
    });

    uploadStartedEventKeys.forEach((key) => {
      this.appEvents.on(`${wizardComposerEdtiorEventPrefix}:${key}`, () => {
        this.set("uploading", true);
      });
    });
    uploadEndedEventKeys.forEach((key) => {
      this.appEvents.on(`${wizardComposerEdtiorEventPrefix}:${key}`, () => {
        this.set("uploading", false);
      });
    });
  },

  willDestroyElement() {
    this._super(...arguments);
    this.wizardState.clear();
  },

  didInsertElement() {
    this._super(...arguments);
    this.autoFocus();
  },

  @discourseComputed("step.index", "wizard.required")
  showQuitButton: (index, required) => index === 0 && !required,

  showNextButton: not("step.final"),
  showDoneButton: alias("step.final"),
  // `uploading` here tracks composer editor uploads (see
  // `custom-wizard-composer-editor` appEvents). Wizard upload fields do
  // NOT flip this — they track themselves via `wizardState.pendingUploads`
  // so they can flow through the save/advance pipeline without blocking
  // the Next button, per the background-upload design.
  btnsDisabled: or("saving", "uploading"),

  // Done button (final step) is blocked until EVERY upload across the
  // whole wizard has finished, so no field ends up with a null value at
  // submit time. See wizard-state.js for the full design rationale.
  @discourseComputed(
    "saving",
    "uploading",
    "wizardState.hasPendingUploads",
    "step.final"
  )
  finalSubmitDisabled(saving, uploading, hasPending, final) {
    if (saving || uploading) {
      return true;
    }
    return !!final && !!hasPending;
  },

  @discourseComputed(
    "step.index",
    "step.displayIndex",
    "wizard.totalSteps",
    "wizard.completed"
  )
  showFinishButton: (index, displayIndex, total, completed) => {
    return index !== 0 && displayIndex !== total && completed;
  },

  @discourseComputed("step.index")
  showBackButton: (index) => index > 0,

  @discourseComputed("step.banner")
  bannerImage(src) {
    if (!src) {
      return;
    }
    return getUrl(src);
  },

  @discourseComputed("step.id")
  bannerAndDescriptionClass(id) {
    return `wizard-banner-and-description wizard-banner-and-description-${id}`;
  },

  @discourseComputed("step.fields.[]")
  primaryButtonIndex(fields) {
    return fields.length + 1;
  },

  @discourseComputed("step.fields.[]")
  secondaryButtonIndex(fields) {
    return fields.length + 2;
  },

  @observes("step.id")
  _stepChanged() {
    this.set("saving", false);
    this.autoFocus();
  },

  @observes("step.message")
  _handleMessage: function () {
    const message = this.get("step.message");
    this.showMessage(message);
  },

  @discourseComputed("step.fields")
  includeSidebar(fields) {
    return !!fields.findBy("show_in_sidebar");
  },

  autoFocus() {
    discourseLater(() => {
      schedule("afterRender", () => {
        if ($(".invalid .wizard-focusable").length) {
          this.animateInvalidFields();
        }
      });
    });
  },

  animateInvalidFields() {
    schedule("afterRender", () => {
      let $invalid = $(".invalid .wizard-focusable");
      if ($invalid.length) {
        $([document.documentElement, document.body]).animate(
          {
            scrollTop: $invalid.offset().top - 200,
          },
          400
        );
      }
    });
  },

  async advance() {
    this.set("saving", true);
    try {
      // Accept the Next click immediately even while an upload is in
      // flight — the field-level `hasPendingUpload` flag lets
      // validation pass, so the user never sees a "required" error.
      // The navigation itself still waits for uploads to land before
      // sending `step.save()`, because the server needs the final
      // upload URL to persist. The visible effect: the button shows
      // "Saving..." briefly instead of throwing an error.
      await this.wizardState.whenIdle();
      const response = await this.get("step").save();
      updateCachedWizard(CustomWizard.build(response["wizard"]));

      if (response["final"]) {
        CustomWizard.finished(response);
      } else {
        this.goNext(response);
      }
    } catch {
      this.animateInvalidFields();
    } finally {
      this.set("saving", false);
    }
  },

  actions: {
    quit() {
      this.get("wizard").skip();
    },

    done() {
      this.send("nextStep");
    },

    showMessage(message) {
      this.showMessage(message);
    },

    stylingDropdownChanged(id, value) {
      this.set("stylingDropdown", { id, value });
    },

    exitEarly() {
      const step = this.step;
      step.validate();

      if (step.get("valid")) {
        this.set("saving", true);

        step
          .save()
          .then(() => this.send("quit"))
          .finally(() => this.set("saving", false));
      } else {
        this.autoFocus();
      }
    },

    backStep() {
      if (this.saving) {
        return;
      }

      this.goBack();
    },

    nextStep() {
      if (this.saving) {
        return;
      }

      this.step.validate();

      if (this.step.get("valid")) {
        this.advance();
      } else {
        this.autoFocus();
      }
    },
  },
});

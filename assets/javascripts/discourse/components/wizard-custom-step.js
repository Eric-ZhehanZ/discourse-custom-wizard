import Component from "@ember/component";
import { action } from "@ember/object";
import discourseComputed from "discourse-common/utils/decorators";

function normalizeSlug(raw) {
  return raw
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export default Component.extend({
  classNames: "wizard-custom-step",

  init() {
    this._super(...arguments);
    this.set("pendingSlug", this.step?.id || "");
  },

  @discourseComputed("step.index")
  stepConditionOptions(stepIndex) {
    const options = {
      inputTypes: "validation",
      context: "step",
      textSelection: "value",
      userFieldSelection: true,
      groupSelection: true,
    };

    if (stepIndex > 0) {
      options["wizardFieldSelection"] = true;
      options["wizardActionSelection"] = true;
    }

    return options;
  },

  // Apply a renamed slug to step.id and propagate to every
  // wizard.action.run_after that was pointing at the old id. Falls
  // back to the original id if the input normalizes to empty or is
  // already taken by another step.
  @action
  commitSlug() {
    const raw = this.pendingSlug;
    const oldId = this.step.id;
    const next = normalizeSlug(raw);

    if (!next || next === oldId) {
      this.set("pendingSlug", oldId);
      return;
    }

    const sibling = this.wizard?.steps?.find(
      (s) => s !== this.step && s?.get?.("id") === next
    );
    if (sibling) {
      this.set("pendingSlug", oldId);
      return;
    }

    if (this.wizard?.actions) {
      this.wizard.actions.forEach((a) => {
        if (!a) {
          return;
        }
        const current = a.get ? a.get("run_after") : a.run_after;
        if (current === oldId) {
          a.set ? a.set("run_after", next) : (a.run_after = next);
        }
      });
    }

    this.step.set("id", next);
    this.set("pendingSlug", next);
  },

  actions: {
    bannerUploadDone(upload) {
      this.setProperties({
        "step.banner": upload.url,
        "step.banner_upload_id": upload.id,
      });
    },

    bannerUploadDeleted() {
      this.setProperties({
        "step.banner": null,
        "step.banner_upload_id": null,
      });
    },
  },
});

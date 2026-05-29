import EmberObject from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import User from "discourse/models/user";
import getUrl from "discourse-common/lib/get-url";
import discourseComputed from "discourse-common/utils/decorators";
import CustomWizardField from "./custom-wizard-field";
import CustomWizardStep from "./custom-wizard-step";

const CustomWizard = EmberObject.extend({
  @discourseComputed("steps.length")
  totalSteps: (length) => length,

  skip() {
    // A forced (required) wizard normally can't be skipped — but a
    // soft-skip-enabled one can, while the user still has skips left and
    // the deadline hasn't passed (server-authoritative `skip_allowed`).
    if (
      this.required &&
      !this.completed &&
      this.permitted &&
      !this.skip_allowed
    ) {
      return;
    }
    CustomWizard.skip(this.id);
  },

  restart() {
    CustomWizard.restart(this.id);
  },
});

CustomWizard.reopenClass({
  skip(wizardId) {
    ajax({ url: `/w/${wizardId}/skip`, type: "PUT" })
      .then((result) => {
        // The server returns `{ locked: true }` for delayed-approval users
        // whose lockdown forbids skipping. Treat it as a silent no-op so we
        // neither navigate away (which would bounce through the redirect
        // middleware) nor show an alarming error dialog — the user is
        // already on the correct page and should just stay there.
        if (result && result.locked) {
          return;
        }
        // Soft-skip: stop the page:changed initializer from bouncing the
        // user straight back to the wizard for the rest of this session.
        // The server keeps redirect_to_wizard set for deadline
        // enforcement and re-serializes it (un-suppressed) after the
        // snooze elapses / on the next full load, so the prompt returns.
        const currentUser = User.current();
        if (currentUser) {
          currentUser.set("redirect_to_wizard", null);
        }
        CustomWizard.finished(result);
      })
      .catch(popupAjaxError);
  },

  restart(wizardId) {
    ajax({ url: `/w/${wizardId}/skip`, type: "PUT" })
      .then((result) => {
        if (result && result.locked) {
          return;
        }
        DiscourseURL.redirectTo(getUrl(`/w/${wizardId}`));
      })
      .catch(popupAjaxError);
  },

  finished(result) {
    let url = "/";
    if (result.redirect_on_complete) {
      url = result.redirect_on_complete;
    }
    // routeTo navigates via Ember when the URL is internal, falling
    // back to a hard reload only when the URL crosses origins or the
    // router can't resolve it. redirectTo always reloads. The SPA
    // transition skips the homepage flash and keeps the wizard
    // contextual state alive (no full re-bootstrap).
    DiscourseURL.routeTo(getUrl(url));
  },

  build(wizardJson) {
    if (!wizardJson) {
      return null;
    }

    if (!wizardJson.completed && wizardJson.steps) {
      wizardJson.steps = wizardJson.steps
        .map((step) => {
          const stepObj = CustomWizardStep.create(step);
          stepObj.wizardId = wizardJson.id;

          stepObj.fields.sort((a, b) => {
            return parseFloat(a.number) - parseFloat(b.number);
          });

          let tabindex = 1;
          stepObj.fields.forEach((f) => {
            f.tabindex = tabindex;

            if (["date_time"].includes(f.type)) {
              tabindex = tabindex + 2;
            } else {
              tabindex++;
            }
          });

          stepObj.fields = stepObj.fields.map((f) => {
            f.wizardId = wizardJson.id;
            f.stepId = stepObj.id;
            return CustomWizardField.create(f);
          });

          return stepObj;
        })
        .sort((a, b) => {
          return parseFloat(a.index) - parseFloat(b.index);
        });
    }
    return CustomWizard.create(wizardJson);
  },
});

export function findCustomWizard(wizardId, params = {}) {
  let url = `/w/${wizardId}.json`;

  let paramKeys = Object.keys(params).filter((k) => {
    if (k === "wizard_id") {
      return false;
    }
    return !!params[k];
  });

  if (paramKeys.length) {
    url += "?";
    paramKeys.forEach((k, i) => {
      if (i > 0) {
        url += "&";
      }
      url += `${k}=${params[k]}`;
    });
  }

  return ajax(url).then((result) => {
    return CustomWizard.build(result);
  });
}

let _wizard_store;

export function updateCachedWizard(wizard) {
  _wizard_store = wizard;
}

export function getCachedWizard() {
  return _wizard_store;
}

export default CustomWizard;

import Controller from "@ember/controller";
import { or } from "@ember/object/computed";
import discourseComputed from "discourse-common/utils/decorators";

const reasons = {
  noWizard: "none",
  requiresLogin: "requires_login",
  notPermitted: "not_permitted",
  completed: "completed",
};

export default Controller.extend({
  noAccess: or("noWizard", "requiresLogin", "notPermitted", "completed"),

  // The new wizard status page handles approved/pending/denied. The
  // legacy noAccess view still renders for the truly-no-access reasons
  // (no wizard, no login, no permission, completed-and-done).
  @discourseComputed("reviewState")
  showStatusPage(state) {
    return state && state !== "none";
  },

  @discourseComputed("noAccessReason")
  noAccessI18nKey(reason) {
    return reason ? `wizard.${reasons[reason]}` : "wizard.none";
  },

  @discourseComputed
  noAccessReason() {
    return Object.keys(reasons).find((reason) => this.get(reason));
  },
});

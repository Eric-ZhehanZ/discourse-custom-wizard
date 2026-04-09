import Component from "@ember/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import discourseComputed from "discourse-common/utils/decorators";
import { i18n } from "discourse-i18n";
import {
  checkUploadSize,
  transformFileForUpload,
} from "../lib/wizard-image-transforms";

export default class CustomWizardFieldUpload extends Component {
  @service siteSettings;
  @service wizardState;
  @service dialog;

  // Stage label shown on the button while transforms run before the
  // actual upload begins ("converting" | "compressing" | null).
  preparingStage = null;
  // Set to true from the moment the user picks a file until Uppy's
  // `uploadDone` fires. Used (together with the Uppy `uploading` flag) to
  // lock the button and show spinners.
  processing = false;
  // When we call `wizardState.registerUpload()` we flip this so we know to
  // call `releaseUpload()` exactly once on completion / failure / destroy.
  pendingRegistered = false;

  @action
  setup() {
    this.uppyUpload = new UppyUpload(getOwner(this), {
      id: this.inputId,
      type: `wizard_${this.field.id}`,
      uploadDone: (upload) => {
        this.setProperties({
          "field.value": upload,
          "field.hasPendingUpload": false,
          isImage: this.imageUploadFormats.includes(upload.extension),
        });
        this.#releasePending();
        this.set("processing", false);
        // NOTE: do NOT call `this.done()` here. `done` is not a method
        // on this component and no parent passes it via `{{component}}`.
        // The call was dead code inherited from a much older template
        // that once wired up a `done` action. Calling an undefined
        // property throws a TypeError synchronously inside Uppy's
        // `upload-success` handler, which aborted the handler before
        // `#triggerInProgressUploadsEvent()` and `#allUploadsComplete()`
        // ran. The consequence was that `UppyUpload#reset()` never
        // fired, leaving `uploading` true, `uploadProgress` stuck at
        // 100, and Uppy's internal file list populated — so the button
        // was locked at "Uploading 100%" and the next `addFiles` call
        // tripped the "Cannot upload more than 1 file" guard.
      },
    });
    // Intentionally call `setup()` with no file input so UppyUpload does
    // NOT bind its own change listener. We handle file selection ourselves
    // in `onFileChange` to run transforms before handing the file to Uppy.
    this.uppyUpload.setup();
  }

  willDestroyElement() {
    super.willDestroyElement(...arguments);
    // If the component is torn down mid-upload (e.g. navigation), keep the
    // global counter honest so the Done button isn't stuck disabled.
    this.#releasePending();
  }

  get imageUploadFormats() {
    return this.siteSettings.wizard_recognised_image_upload_formats.split("|");
  }

  get inputId() {
    return `wizard_field_upload_${this.field?.id}`;
  }

  get wrapperClass() {
    let result = "wizard-field-upload";
    if (this.isImage) {
      result += " is-image";
    }
    if (this.fieldClass) {
      result += ` ${this.fieldClass}`;
    }
    return result;
  }

  // The effective size cap for this field: per-field override, falling
  // back to the site-wide `wizard_max_upload_size_kb`. Uses a nullish
  // check so an explicit `0` (which the server-side validator treats as
  // "no cap") is preserved instead of falling through to the site
  // default. `checkUploadSize` interprets 0 the same way.
  get effectiveMaxUploadSizeKb() {
    const override = this.field?.max_upload_size_kb;
    return override != null && override !== ""
      ? override
      : this.siteSettings.wizard_max_upload_size_kb;
  }

  get isBusy() {
    return this.processing || this.uppyUpload?.uploading;
  }

  // Uppy exposes `uploadProgress` as undefined/null before the first
  // chunk lands, which would produce `aria-valuenow="undefined"` and
  // an `NaN%` inline width. Default to 0 so the progressbar is always
  // valid ARIA and visually flat at the start.
  get uploadProgressValue() {
    return this.uppyUpload?.uploadProgress || 0;
  }

  @discourseComputed(
    "processing",
    "preparingStage",
    "uppyUpload.uploading",
    "uppyUpload.uploadProgress"
  )
  uploadLabel(processing, preparingStage, uploading, progress) {
    if (preparingStage === "converting") {
      return i18n("wizard.upload_converting");
    }
    if (preparingStage === "compressing") {
      return i18n("wizard.upload_compressing");
    }
    if (processing && !uploading) {
      return i18n("wizard.upload_preparing");
    }
    if (uploading) {
      return `${i18n("wizard.uploading")} ${progress || 0}%`;
    }
    return i18n("wizard.upload");
  }

  #registerPending() {
    if (!this.pendingRegistered) {
      this.wizardState.registerUpload();
      this.set("pendingRegistered", true);
    }
    if (this.field) {
      this.set("field.hasPendingUpload", true);
    }
  }

  #releasePending() {
    if (this.pendingRegistered) {
      this.wizardState.releaseUpload();
      this.set("pendingRegistered", false);
    }
    if (this.field) {
      this.set("field.hasPendingUpload", false);
    }
  }

  #handleError(error) {
    this.#releasePending();
    this.setProperties({
      processing: false,
      preparingStage: null,
    });
    this.dialog.alert(error);
  }

  @action
  chooseFiles() {
    // The file input is rendered inline in the template (see .hbs). Click
    // it programmatically so users see the normal OS picker.
    const inputEl = document.getElementById(this.inputId);
    if (inputEl) {
      inputEl.value = "";
      inputEl.click();
    }
  }

  @action
  async onFileChange(event) {
    const file = event?.target?.files?.[0];
    if (!file) {
      return;
    }

    this.setProperties({
      processing: true,
      preparingStage: null,
    });
    this.#registerPending();

    const onStage = (stage) => this.set("preparingStage", stage);

    let transformed;
    try {
      transformed = await transformFileForUpload(
        file,
        {
          convertHeic: this.field?.convert_heic,
          compressImages: this.field?.compress_images,
          maxImageDimension: this.field?.max_image_dimension,
          maxUploadSizeKb: this.effectiveMaxUploadSizeKb,
        },
        onStage
      );
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("wizard: unexpected transform error", e);
      transformed = file;
    }

    this.set("preparingStage", null);

    // Size gate AFTER transforms — if compression brought the file under
    // the limit we accept it, otherwise we reject with a clear message.
    const check = checkUploadSize(transformed, this.effectiveMaxUploadSizeKb);
    if (!check.ok) {
      this.#handleError(
        i18n("wizard.upload_file_too_large", {
          actual: check.actualKb,
          max: check.maxKb,
        })
      );
      return;
    }

    try {
      await this.uppyUpload.addFiles([transformed]);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("wizard: addFiles failed", e);
      this.#handleError(i18n("wizard.upload_error"));
    }
  }
}

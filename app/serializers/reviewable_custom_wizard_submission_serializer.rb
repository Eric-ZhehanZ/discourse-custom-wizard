# frozen_string_literal: true

class ReviewableCustomWizardSubmissionSerializer < ReviewableSerializer
  payload_attributes :wizard_id, :submission_id, :submission_fields, :actions

  attributes :wizard_id,
             :wizard_name,
             :action_count,
             :submission_user,
             :enriched_fields,
             :enriched_actions

  SKIP_FIELD_KEYS = %w[
    id
    route_to
    redirect_on_complete
    redirect_to
    submitted_at
    updated_at
    permitted_param_keys
  ].freeze

  def wizard_id
    object.wizard_id
  end

  def wizard_name
    object.wizard_name
  end

  def action_count
    object.actions_payload.size
  end

  def submission_user
    user = object.created_by || (object.target if object.target.is_a?(User))
    return nil unless user.is_a?(User)

    {
      id: user.id,
      username: user.username,
      name: user.name,
      avatar_template: user.avatar_template,
      profile_url: "/u/#{user.username}",
      admin_url: scope&.is_staff? ? "/admin/users/#{user.id}/#{user.username}" : nil,
      email: scope&.is_staff? ? user.email : nil,
    }
  end

  # Resolve field IDs to the labels that were configured on the wizard at
  # serialization time. We don't snapshot labels into the payload so a
  # later wizard rename is reflected, but we fall back to the raw id if
  # the field has since been removed. Upload-type values get classified
  # so the client can render thumbnails instead of a raw JSON blob.
  def enriched_fields
    fields_payload = object.payload&.dig("submission_fields") || {}
    field_map = build_field_label_map

    fields_payload.filter_map do |key, value|
      next if SKIP_FIELD_KEYS.include?(key.to_s)

      type, display, upload = classify(value)
      {
        id: key.to_s,
        label: field_map[key.to_s] || key.to_s,
        type: type,
        value: display,
        upload: upload,
      }
    end
  end

  # Pass action types through so the client can localize via
  # `admin.wizard.action.<type>.label`. Include the action id and the
  # configured label too (admin can override the wizard's display name).
  def enriched_actions
    object.actions_payload.map do |a|
      {
        id: a["id"],
        type: a["type"],
        label: a["label"],
      }
    end
  end

  private

  def build_field_label_map
    template = object.wizard_template
    return {} unless template.is_a?(Hash)

    {}.tap do |map|
      Array(template["steps"]).each do |step|
        Array(step["fields"]).each do |field|
          next unless field.is_a?(Hash) && field["id"]
          map[field["id"].to_s] = field["label"].presence || field["id"].to_s
        end
      end
    end
  end

  def stringify(value)
    case value
    when nil
      ""
    when Hash, Array
      value.to_json
    else
      value.to_s
    end
  end

  def classify(value)
    if value.is_a?(Hash) && value["url"].is_a?(String) && (value["extension"] || value["width"])
      filename = value["original_filename"].presence || value["url"]
      upload = { url: value["url"], filename: filename }
      return ["upload", filename, upload]
    end

    ["text", stringify(value), nil]
  end
end

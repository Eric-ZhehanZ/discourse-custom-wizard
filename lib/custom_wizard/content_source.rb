# frozen_string_literal: true

# Bulk-text and remote-URL alternatives to the mapper-based "content"
# editor for dropdown/tag/category/group/topic fields.
#
# Format (shared by text and remote):
#   - one option per non-empty, non-comment line
#   - lines beginning with '#' are ignored
#   - if the line contains the separator (default '|'), it is split into
#     [key, value]; the value is shown in the dropdown and the key is the
#     stored choice. Otherwise key == value == the trimmed line.
module CustomWizard::ContentSource
  DEFAULT_SEPARATOR = "|"
  REMOTE_CACHE_TTL = 5.minutes
  REMOTE_MAX_BYTES = 256 * 1024
  REMOTE_TIMEOUT = 10

  def self.build(field_template)
    case field_template["content_source"].to_s
    when "text"
      parse(field_template["content_text"].to_s, field_template["content_separator"])
    when "remote"
      url = field_template["content_url"].to_s
      return nil if url.blank?
      body = fetch_remote(url)
      return nil if body.blank?
      parse(body, field_template["content_separator"])
    end
  end

  def self.parse(text, separator = nil)
    sep = (separator.presence || DEFAULT_SEPARATOR).to_s
    text
      .to_s
      .each_line
      .map(&:strip)
      .reject { |line| line.empty? || line.start_with?("#") }
      .map do |line|
        if line.include?(sep)
          key, value = line.split(sep, 2).map(&:strip)
          { id: key, name: value.presence || key }
        else
          { id: line, name: line }
        end
      end
  end

  def self.fetch_remote(url)
    cache_key = "custom_wizard:content_source:#{Digest::SHA1.hexdigest(url)}"
    cached = Discourse.cache.read(cache_key)
    return cached if cached

    body = http_get(url)
    Discourse.cache.write(cache_key, body, expires_in: REMOTE_CACHE_TTL) if body
    body
  rescue StandardError => e
    Rails.logger.warn("custom_wizard content_source remote fetch failed (#{url}): #{e.class}: #{e.message}")
    nil
  end

  def self.http_get(url)
    fd = FinalDestination.new(url, timeout: REMOTE_TIMEOUT, follow_canonical: true)
    resolved = fd.resolve
    return nil unless resolved

    Net::HTTP.start(resolved.host, resolved.port, use_ssl: resolved.scheme == "https",
                                                  open_timeout: REMOTE_TIMEOUT,
                                                  read_timeout: REMOTE_TIMEOUT) do |http|
      req = Net::HTTP::Get.new(resolved.request_uri,
                               "User-Agent" => "Discourse Custom Wizard")
      res = http.request(req)
      return nil unless res.is_a?(Net::HTTPSuccess)
      body = res.body.to_s
      return nil if body.bytesize > REMOTE_MAX_BYTES
      body
    end
  end
end

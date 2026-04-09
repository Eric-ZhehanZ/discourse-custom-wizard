# Full Mandarin (zh_CN) Language Support

## Problem

The plugin currently ships two "Chinese" locale files that are effectively dead code and leave Simplified Chinese users with an untranslated experience:

- `config/locales/client.zh.yml` — top-level YAML key is `zh-TW:` (dash), and every value is the original English string. It was generated as a Crowdin template and never translated.
- `config/locales/server.zh.yml` — top-level YAML key is `zh-CN:` (dash). About ten strings have real Chinese translations (e.g. `"未选中任何文件"`, `"文件过大"`); the rest are English.

Both files are orphaned. Discourse core registers Chinese as `zh_CN` and `zh_TW` (underscore), so neither `zh-CN` nor `zh-TW` matches any registered locale and the translations in these files are loaded into namespaces that nothing reads. A user who selects Simplified Chinese in Discourse sees raw English for every plugin string.

The Crowdin pipeline that produced these files is the root cause: `crowdin.yml` uses `%two_letters_code%`, which cannot produce `zh_CN.yml` / `zh_TW.yml` names, so Crowdin can never fix this on its own.

## Goal

Add fully translated Simplified Chinese (`zh_CN`) support to the plugin and fix the Crowdin pipeline so the fix is not undone on the next sync:

1. Ship `config/locales/client.zh_CN.yml` and `config/locales/server.zh_CN.yml` with every key from the English sources translated into Simplified Chinese, top-level key `zh_CN:`.
2. Delete the broken `client.zh.yml` and `server.zh.yml` files, salvaging the ~10 real Chinese strings from the server file into the new zh_CN file before deletion.
3. Update `crowdin.yml` with a `languages_mapping` block so that Chinese variants are exported as `zh_CN` / `zh_TW` instead of the ambiguous `zh` two-letter code.

Success criterion: on a Discourse instance running this plugin with default locale set to 简体中文, every plugin-rendered string in the wizard UI, the wizard admin UI, error messages, and the plugin's site-setting descriptions is displayed in Simplified Chinese.

## Non-goals

- **Traditional Chinese (zh_TW).** Not requested. The `crowdin.yml` mapping includes `zh-TW → zh_TW` for forward-compatibility, but no `client.zh_TW.yml` file is created and no Traditional Chinese translation work is performed.
- **Discourse core locale registration.** The plugin does not need a `register_locale` call. Discourse core already registers `zh_CN` and `zh_TW`, and Rails autoloads every `config/locales/*.yml` in every plugin directory via `config.i18n.load_path`. New files picked up with the correct top-level YAML key "just work."
- **Source code changes.** No Ruby or JS files are modified. All display strings already go through `I18n.t` with locale-neutral keys.
- **Plugin README / documentation translation.** Out of scope.
- **Moment.js locales, timezone names, pluralization rules.** Provided by Discourse core's `zh_CN` registration.
- **Backfilling the English source files.** `client.en.yml` and `server.en.yml` are the canonical source of truth and are not touched.

## Design

### File changes overview

| File | Action |
|---|---|
| `config/locales/client.zh_CN.yml` | **Create** — full translation of every key in `client.en.yml`, top-level key `zh_CN:` |
| `config/locales/server.zh_CN.yml` | **Create** — full translation of every key in `server.en.yml`, top-level key `zh_CN:` |
| `config/locales/client.zh.yml` | **Delete** — broken; labeled `zh-TW:` but untranslated |
| `config/locales/server.zh.yml` | **Delete** — broken; labeled `zh-CN:` but mostly English. Salvage ~10 real Chinese strings first. |
| `crowdin.yml` | **Update** — add `languages_mapping` for `zh-CN` / `zh-TW` |
| `plugin.rb` | Unchanged |
| `config/settings.yml` | Unchanged |
| Any Ruby/JS source | Unchanged |

### How Discourse loads these files

This is the mechanism the design relies on; it is worth writing down because the current broken state is caused by a misunderstanding of it.

1. In `discourse/config/application.rb`:
   ```ruby
   config.i18n.load_path += Dir["#{Rails.root}/plugins/*/config/locales/*.yml"]
   ```
   **Every** `config/locales/*.yml` file inside any plugin is loaded by Rails I18n at boot. The filename is irrelevant to which locale the translations end up in. The **top-level YAML key** is what matters.

2. Discourse core registers a known set of locales via `DiscoursePluginRegistry.register_locale` — for Chinese, it registers `zh_CN` and `zh_TW` (see `discourse/config/locales/names.yml:554–559`).

3. When a user selects "简体中文" in their preferences, I18n looks up keys under the `zh_CN` namespace. A plugin YAML file contributes to that lookup only if its top-level key is exactly `zh_CN:` — not `zh-CN:`, not `zh:`, not `zh-cn:`.

4. The `crowdin.yml` `translation:` field controls filename generation during a Crowdin pull. With `%two_letters_code%`, both Simplified and Traditional Chinese collapse into a single `client.zh.yml` file with no way to distinguish them. `languages_mapping` is Crowdin's documented override for this.

### Content strategy for the new zh_CN files

#### Source of truth
`client.en.yml` and `server.en.yml` are read verbatim. Every key present in those files must appear, with identical nesting, in the corresponding `zh_CN` file. No keys added, none dropped.

#### Salvaged strings
Before deleting `server.zh.yml`, these translations are copied into the new `server.zh_CN.yml` at the same key paths (values unchanged):

| Key path | Value |
|---|---|
| `wizard.custom_field.error.save_default` | `保存自定义字段“%{name}”失败` |
| `wizard.export.error.select_one` | `请选择至少一个有效向导` |
| `wizard.import.error.no_file` | `未选中任何文件` |
| `wizard.import.error.file_large` | `文件过大` |
| `wizard.import.error.invalid_json` | `文件不是一个有效的 json 文件` |
| `wizard.destroy.error.no_template` | `没有找到模板` |
| `wizard.destroy.error.default` | `销毁向导时出错` |
| `wizard.validation.conflict` | `Id 为 %{wizard_id} 的向导已存在` |
| `wizard.validation.after_signup` | `您只能有一个“注册即导向”型的向导。Id为 %{wizard_id} 的向导已启用该特性。` |
| `site_settings.custom_wizard_enabled` | `启用自定义向导。` |

`client.zh.yml` contributes nothing salvageable — it is English throughout.

#### Terminology — aligned with Discourse core's `client.zh_CN.yml`

Users read the plugin's Chinese alongside Discourse core's Chinese, so the same concepts must use the same words. The authoritative reference is `discourse/config/locales/client.zh_CN.yml`; the plugin follows it.

| English | zh_CN |
|---|---|
| Wizard | 向导 |
| Step | 步骤 |
| Field | 字段 |
| Action | 操作 |
| Custom field | 自定义字段 |
| Post | 帖子 |
| Topic | 主题 |
| Category | 分类 |
| Tag | 标签 |
| Group | 群组 |
| User / User field | 用户 / 用户字段 |
| Composer | 编辑器 |
| Preview | 预览 |
| Required | 必填 |
| Upload / Download | 上传 / 下载 |
| Submissions | 提交记录 |
| Notification | 通知 |
| Validation | 验证 |
| API / URL / JSON / OAuth | (untranslated — keep as-is) |

Proper nouns of the Discourse project (e.g. "Discourse", "Crowdin") are kept in English. Technical acronyms (API, URL, JSON, OAuth, HTTP, SSO) are kept in English — this matches Discourse core's convention.

#### Preservation rules (non-negotiable)

These are validated in the verification step and are mechanical:

1. **Interpolation placeholders are byte-identical.** Every `%{name}`, `%{count}`, `%{wizard_id}`, `{{name}}`, `{{action}}`, `{{count}}`, `{{messages}}`, etc. in the English source must appear unchanged in the Chinese translation. Never translate the variable name itself (`{{名称}}` would break the template).
2. **HTML and Markdown are preserved.** The one case of embedded HTML in the current sources is `field.date_time_format.instructions` under `admin_js`, which contains an `<a href="...">Moment.js format</a>` anchor. The anchor tag, its `href`, and its `target` attribute are preserved; only the anchor text is translated.
3. **Pluralization keys are preserved.** YAML keys like `other:` (and `one:` where present) inside a pluralized entry such as `x_characters` are kept as keys — they are not translated and not renamed.
4. **Key order and nesting match the English file.** Makes diffing future updates straightforward.
5. **Top-level key is `zh_CN:`** (underscore). Never `zh-CN`, `zh`, or `zh_cn`.
6. **Encoding is UTF-8 without BOM**, Unix line endings, trailing newline — matches repository convention.

### `crowdin.yml` update

Current:

```yaml
pull_request_title: "I18n: Update translations"
files:
  - source: /config/locales/client.en.yml
    translation: /config/locales/client.%two_letters_code%.yml
  - source: /config/locales/server.en.yml
    translation: /config/locales/server.%two_letters_code%.yml
```

New:

```yaml
pull_request_title: "I18n: Update translations"
files:
  - source: /config/locales/client.en.yml
    translation: /config/locales/client.%two_letters_code%.yml
    languages_mapping:
      two_letters_code:
        zh-CN: zh_CN
        zh-TW: zh_TW
  - source: /config/locales/server.en.yml
    translation: /config/locales/server.%two_letters_code%.yml
    languages_mapping:
      two_letters_code:
        zh-CN: zh_CN
        zh-TW: zh_TW
```

Effect: for every language except the two Chinese variants, Crowdin keeps producing two-letter-code filenames (`client.fr.yml`, `client.de.yml`, etc.), so no existing file is renamed or disturbed. For Chinese, Crowdin produces `client.zh_CN.yml` and `client.zh_TW.yml`, matching Discourse core's convention and leaving the new hand-written file at a path Crowdin will maintain in the future.

### Verification

Performed at the end of the implementation plan, before committing:

1. **YAML parse.** Both new files parse cleanly with `YAML.safe_load_file` in Ruby. No tab characters, no unquoted strings that YAML misinterprets as booleans, no dangling mappings.
2. **Top-level key is exactly `zh_CN:`.** Single assertion per file.
3. **Key-set equivalence.** Flatten both English and Chinese files to the set of dotted key paths (`js.wizard.complete_custom`, etc.). The zh_CN set must equal the en set. Any diff is a bug. Script: a short Ruby one-liner using `YAML.safe_load_file` and recursive key collection.
4. **Placeholder preservation.** For each string value in the English source, extract every `%{…}` and `{{…}}` token and assert the same multiset appears in the zh_CN value. Catches typos and accidental translation of variable names.
5. **HTML tag preservation.** For strings containing `<…>`, assert the tag structure (open/close tag names and attribute names) survives translation. Only the `field.date_time_format.instructions` key is expected to match, but the check is cheap and general.
6. **No literal English leakage in high-visibility strings.** Grep the resulting zh_CN file for strings that are still pure ASCII English sentences (longer than, say, 10 chars with no CJK characters). Some ASCII is legitimate (URLs, single characters like `B` / `I` for bold/italic button labels, acronyms) so this is a manual review list, not an automated fail gate.
7. **Load smoke test.** In the implementation plan, include a step to boot the plugin in the dev environment, set site language to 简体中文, open the custom wizard admin page and a sample published wizard, and visually confirm strings render in Chinese.

Steps 1–5 are blocking. Steps 6–7 are manual checkpoints in the plan.

### Risk / rollback

- **Blast radius is contained.** Only three files change (two deleted, two created, one updated). No runtime code, no DB migration, no settings, no plugin API.
- **Rollback is a simple `git revert`.** Users currently see English; after revert they still see English. No state migration required.
- **Worst-case bug is visible but non-destructive.** If a key is mistranslated the user sees the wrong word; if a placeholder is dropped the user sees a literal `%{name}` in the UI. Neither breaks the wizard functionally.
- **Crowdin interaction.** The `languages_mapping` update is a no-op for all non-Chinese languages. The first Crowdin sync after this change will produce `client.zh_CN.yml` at the same path as our hand-written file; Crowdin's merge semantics will then be the source of truth for community edits. Our initial translation seeds that Crowdin project.

## Implementation order

1. Read `client.en.yml` and `server.en.yml` in full to capture the key graph.
2. Draft `server.zh_CN.yml` first (smaller — ~72 lines in the English source) and use it as a warm-up for terminology choices.
3. Draft `client.zh_CN.yml` (~660 lines in the English source), consulting Discourse core's `client.zh_CN.yml` wherever the same term already has an established translation.
4. Merge the 10 salvaged strings into `server.zh_CN.yml` (overriding the draft values with the salvaged ones where keys collide).
5. Run the verification script (steps 1–5 above) against both files.
6. Update `crowdin.yml` with `languages_mapping`.
7. Delete `client.zh.yml` and `server.zh.yml`.
8. Final manual smoke test in dev environment (step 7).
9. Commit.

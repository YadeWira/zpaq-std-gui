# Translating ZPAQ-std

Every text that ZPAQ-std shows comes from a language file in this folder: `en.zsl` (English) and
`es.zsl` (Spanish) today. A new language is one new file. You do not need to change or build the program.

## The files

- `en.zsl` is the reference. It is also compiled into the program, so English always works, even when
  the `lang` folder is missing. Start every translation from a copy of it.
- A file is named after its language code: `fr.zsl` (French), `pt-br.zsl` (Portuguese, Brazil),
  `es-cl.zsl` (Spanish, Chile). Use lower case, with `-` between the language and the country.
- The program looks for the files in the `lang` folder next to `zpaq-std-gui.exe`.

## Format

```
; a comment line starts with ';' or '#'
[section]
key = value
```

- Save the file as UTF-8. A BOM is allowed, but not needed. Both LF and CRLF line ends work.
- Only change what is to the right of the first `=`. Keep every key and every `[section]` exactly as
  in `en.zsl`.
- Spaces around the value are removed. To keep a leading or trailing space, write `\s`.
- Escapes: `\n` starts a new line, `\t` is a tab, `\\` is a backslash.
- Words in braces, such as `{name}`, `{file}` or `{n}`, are filled in by the program. Copy them
  unchanged. You may move them within the sentence, for example `{n} archivos` or `archivos: {n}`.
- Plurals: a key that ends in `.one` is used for exactly 1, and `.other` for every other number. If your
  language uses the same form for all numbers, give only `.other`.
- If the same key appears twice, the last one wins.

## Sections

| Section | What it holds |
|---|---|
| `[info]` | `code`, `name` (the language's own name, as shown in Settings, for example `Français`), `english_name`, `author`, `app_version` (the version the file was written for) |
| `[formmain]` and the other `[form...]` sections | texts of a window. A key is a component name, for example `tbopen` (a toolbar button) or `actopen` (a command, used in the menu). `<name>.hint` is its tooltip, and `<name>.texthint` is the grey text inside an empty box. |
| `[keys]` | key names in the shortcuts that menus show next to a command (`enter = Intro` gives `Alt+Intro`) |
| other sections (`[status]`, `[msg]`, `[about]`, `[cmdline]`, ...) | messages that the program builds while it runs, grouped by topic |

Key names may change between versions, so `app_version` says which version a file matches.

## How a text is chosen

For each key the program tries, in this order:

1. the chosen file, for example `es-cl.zsl`;
2. its base language, `es.zsl`;
3. the English compiled into the program;
4. if the key is found nowhere, the key itself in angle brackets, for example `⟨status.ready⟩`. That
   means a key is missing from `en.zsl`, which is a bug in the program.

So a regional file such as `es-cl.zsl` only needs the lines that differ from `es.zsl`.

## Choosing the language

- By default (`language=auto` in `zpaq-std-gui.ini`), the program uses the Windows display language. On
  Linux it uses `LC_ALL`, `LC_MESSAGES` or `LANG`. It tries the regional file first (`es-cl`), then the base
  language (`es`), then English.
- `language=fr` in the `[gui]` section of `zpaq-std-gui.ini` picks a language.
- `zpaq-std-gui --lang fr` picks it for one run, and `--lang C:\path\fr.zsl` tests a file that is not in
  the `lang` folder yet.
- If the chosen file cannot be loaded, the program uses English and says so in the status bar.

## Checking a translation

Run the program with `--lang <your code>` and open every window. Then compare your file with `en.zsl`:
both must have the same keys, and each line must have the same `{...}` words. A text that is too long
for its button is cut off, so keep toolbar and button texts short.

Please send new or corrected files to the project: <https://github.com/YadeWira/zpaq-std-gui>.

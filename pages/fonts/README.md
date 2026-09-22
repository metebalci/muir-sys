# `pages/fonts/`

These are the three families the page uses. They are carried here so that
reading the page asks nothing of a third party. They are the same files as
ozd's page carries (<https://github.com/metebalci/ozd>, `site/fonts/`),
copied unchanged.

| file | face | used for |
|---|---|---|
| `dela-gothic-one.woff2` | Dela Gothic One | the display face: the wordmark |
| `zen-maru-gothic-500.woff2` | Zen Maru Gothic Medium | the voice, which is what the page calls normal |
| `zen-maru-gothic-700.woff2` | Zen Maru Gothic Bold | the voice, emphasized, and the lede |
| `ibm-plex-mono-400.woff2` | IBM Plex Mono Regular | the eyebrows and the who-line |
| `ibm-plex-mono-500.woff2` | IBM Plex Mono Medium | the keys |

## Where they came from

They were cut from the upstream TTFs in
[google/fonts](https://github.com/google/fonts):
`ofl/delagothicone/DelaGothicOne-Regular.ttf`,
`ofl/zenmarugothic/ZenMaruGothic-Medium.ttf` and `ZenMaruGothic-Bold.ttf`,
and `ofl/ibmplexmono/IBMPlexMono-Regular.ttf` and `IBMPlexMono-Medium.ttf`.
Each file keeps only the code points ozd's page draws: printable ASCII,
`U+00A0` `U+00A9` `U+00B7` `U+2014` `U+2019`, and four katakana this page
does not use.

    pip install fonttools brotli
    pyftsubset DelaGothicOne-Regular.ttf --flavor=woff2 \
        --layout-features+=vert,vrt2 --name-IDs='*' \
        --unicodes=U+0020-007E,U+00A0,U+00A9,U+00B7,U+2014,U+2019,U+30AA,U+30B3,U+30BA,U+30F3 \
        --output-file=dela-gothic-one.woff2

The other four are cut the same way. `--name-IDs='*'` keeps each font's
copyright and license in its own name table.

**A character outside that list is drawn in a fallback face.** Adding one
means cutting the fonts again, with the new code point added to `--unicodes`.

## License

None of the three families is this project's work, and none is under its
license. All three are under the **SIL Open Font License, Version 1.1**,
which permits redistribution with or without modification. The files here
are subsets, and each keeps its copyright notice and license in its
metadata.

- Dela Gothic One, copyright 2020 The Dela Gothic Project Authors ---
  <https://github.com/syakuzen/DelaGothic>
- Zen Maru Gothic, copyright 2021 The Zen Maru Gothic Project Authors ---
  <https://github.com/googlefonts/zen-marugothic>
- IBM Plex Mono, copyright 2017 IBM Corp., with Reserved Font Name "Plex"
  --- <https://github.com/IBM/plex>

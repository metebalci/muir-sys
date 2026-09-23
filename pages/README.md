# pages/

This is muir-sys's project page. Its files are written
by hand, with no build step, no generator and no script. (`site/`, in this
repository, is something else: the site files a Lisp Machine loads.)

- `index.html` is the page. It is brief on purpose, and will grow.
- `style.css` is the stylesheet, in the look of ozd's page
  (<https://ozd.metebalci.com/>): ink and paper with one spot color, and no
  dark mode.
- `mascot.svg` is the mascot: a 3.5-inch diskette with a blank label,
  wearing Cold Boot's face and waving arm, as ozd's page draws CADR, OZ and
  muir-fpga's board. The system is the software, so it is the diskette, and
  its label is blank because the system takes no name of its own.
  `favicon.svg` is the diskette without its face.
- `fonts/` holds the three families, served from here rather than from
  Google. `fonts/README.md` says where they came from and under what license.

`.github/workflows/pages.yml` publishes this directory on every push to
`main` that touches it, and can be run by hand. The page is served at
<https://muir-sys.metebalci.com/>; the domain is set in the repository's Pages
settings, which is why there is no `CNAME` file here.

To look at the page before pushing, open `index.html` in a browser, or serve
the directory:

    python3 -m http.server -d pages 8000

The fonts hold only printable ASCII and a few punctuation marks (see
`fonts/README.md`). A character outside that set is drawn in a fallback face,
so write `&rsquo;`, `&mdash;`, `&middot;` and `&copy;`, and nothing beyond them.

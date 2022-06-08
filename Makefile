emacs ?= $(shell command -v emacs)
wget  ?= $(shell command -v wget)

.PHONY: $(auto) clean distclean test
all:

test:
	$(emacs) -batch -L . -l ert -l test/cool-mode-tests.el \
	-f ert-run-tests-batch-and-exit

README.md : el2markdown.el cool-mode.el
	$(emacs) -batch -l $< cool-mode.el -f el2markdown-write-readme

.INTERMEDIATE: el2markdown.el
el2markdown.el:
	$(wget) -q -O $@ "https://github.com/Lindydancer/el2markdown/raw/master/el2markdown.el"

clean:
	$(RM) *~

distclean: clean
	$(RM) *.elc *autoloads.el *loaddefs.el TAGS

(require 'ert)
(require 'cool-mode)

(defmacro cool--should-indent (from to)
  "Assert text get indented properly in `cool-mode'."
  `(with-temp-buffer
     (let ((cool-indent-offset 2))
       (cool-mode)
       (insert ,from)
       (indent-region (point-min) (point-max))
       (should (equal (buffer-substring-no-properties (point-min)
                                                      (point-max))
                      ,to)))))

(defmacro cool--should-font-lock (text pos face)
  "Assert that TEXT at position POS gets font-locked with FACE in `cool-mode'."
  `(with-temp-buffer
     (cool-mode)
     (insert ,text)
     (if (fboundp 'font-lock-ensure)
         (font-lock-ensure (point-min) (point-max))
       (with-no-warnings
         (font-lock-fontify-buffer)))
     (should (eq ,face (get-text-property ,pos 'face)))))

;; indent

(ert-deftest cool--test-indent-brackets-1 ()
  "Indent inside brackets."
  (cool--should-indent
   "
class Main inherits IO {
main() : SELF_TYPE {}
}"
   "
class Main inherits IO {
  main() : SELF_TYPE {}
}"))

(ert-deftest cool--test-indent-brackets-2 ()
  "indent after brackets"
  (cool--should-indent
   "
class Main inherits IO {
newline() : Object {
out_string(\"\n\")
};
}"
   "
class Main inherits IO {
  newline() : Object {
    out_string(\"\n\")
  };
}"))

(ert-deftest cool--test-indent-parens-1 ()
  "Align lists in parens."
  (cool--should-indent
   "
func(a : Int,
b : Int) : Int {
a + b;
}"
   "
func(a : Int,
     b : Int) : Int {
  a + b;
}"))

(ert-deftest cool--test-indent-if-1 ()
  "if => none hanging"
  (cool--should-indent
   "
if s = 1
then abort()
else newline()
fi"
   "
if s = 1
then abort()
else newline()
fi"))

(ert-deftest cool--test-indent-if-2 ()
  "if => hanging :then"
  (cool--should-indent
   "
if s = \"stop\" then 
abort()
else 
newline()
fi"
   "
if s = \"stop\" then 
  abort()
else 
  newline()
fi"))

(ert-deftest cool--test-indent-if-3 ()
  "if => hanging :else"
  (cool--should-indent
   "
if s = 1 then abort() else
newline() 
fi"
   "
if s = 1 then abort() else
  newline() 
fi"))

(ert-deftest cool--test-indent-elseif-1 ()
  "elseif => hanging :else, :then"
  (cool--should-indent
   "
if s = 1 then abort() else
if s = 2 then 
newline()
else prompt()
fi fi
"
   "
if s = 1 then abort() else
if s = 2 then 
  newline()
else prompt()
fi fi
"))

(ert-deftest cool--test-indent-elseif-2 ()
  "elseif => hanging :then, :else"
  (cool--should-indent
   "
if s = 1 then
abort()
else if s = 2 then
newline() 
else 
s = 3
fi fi"
   "
if s = 1 then
  abort()
else if s = 2 then
  newline() 
else 
  s = 3
fi fi"))

(ert-deftest cool--test-indent-elseif-3 ()
  "elseif => none hanging"
  (cool--should-indent
   "
if s = 1 then abort()
else if s = 2 then newline() 
else s = 3
fi fi"
   "
if s = 1 then abort()
else if s = 2 then newline() 
else s = 3
fi fi"))

(ert-deftest cool--test-indent-while-1 ()
  "basic while loop"
  (cool--should-indent
   "
while true loop
if s = \"stop\" then 
abort()
else 
newline()
fi
pool"
   "
while true loop
  if s = \"stop\" then 
    abort()
  else 
    newline()
  fi
pool"))

(ert-deftest cool--test-indent-let-1 ()
  "basic let .. in"
  (cool--should-indent
   "
\(let s : Int <- 1 in
if s = 1 then
abort()
else
out_string(\"1\")
fi\)"
   "
\(let s : Int <- 1 in
   if s = 1 then
     abort()
   else
     out_string(\"1\")
   fi\)"))

(ert-deftest cool--test-indent-case-1 ()
  "case statement"
  (cool--should-indent
   "
case var of
a : A => var <- a.blah();
o : Object => {
abort(); 0;
};
esac"
   "
case var of
  a : A => var <- a.blah();
  o : Object => {
      abort(); 0;
    };
esac"))

;; font-locking

(ert-deftest cool--test-fl-types ()
  "Font lock types."
  (cool--should-font-lock
   "let s : Int <- new Int in" 9 'font-lock-type-face))

(ert-deftest cool--test-fl-constants ()
  "Font lock true/false"
  (cool--should-font-lock
   "tRUE" 1 'font-lock-constant-face)
  (cool--should-font-lock
   "false" 1 'font-lock-constant-face)
  (cool--should-font-lock
   "fAlse" 1 'font-lock-constant-face)
  (cool--should-font-lock
   "TRUE" 1 nil))

(ert-deftest cool--test-fl-keywords ()
  "Font lock case-insensitive keywords"
  (cool--should-font-lock
   "cLaSs" 1 'font-lock-keyword-face)
  (cool--should-font-lock
   "class" 1 'font-lock-keyword-face))

(provide 'cool-mode-tests)

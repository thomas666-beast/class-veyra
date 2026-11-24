use strict;
use warnings;

use Test::More;

use Class::Veyra::SourceDiff;

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        "same\n",
        "same\n",
    ),
    '',
    'unchanged source produces no diff',
);

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        "first\nold\nlast\n",
        "first\nnew\nlast\n",
    ),
    <<'DIFF',
--- a/example.veyra
+++ b/example.veyra
@@ -1,3 +1,3 @@
 first
-old
+new
 last
DIFF
    'shows changed lines and surrounding context',
);

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        '',
        "new\n",
    ),
    <<'DIFF',
--- a/example.veyra
+++ b/example.veyra
@@ -0,0 +1,1 @@
+new
DIFF
    'shows an insertion into an empty file',
);

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        "old\n",
        '',
    ),
    <<'DIFF',
--- a/example.veyra
+++ b/example.veyra
@@ -1,1 +0,0 @@
-old
DIFF
    'shows deletion of all contents',
);

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        'old',
        "new\n",
    ),
    <<'DIFF',
--- a/example.veyra
+++ b/example.veyra
@@ -1,1 +1,1 @@
-old
\ No newline at end of file
+new
DIFF
    'marks a missing final newline',
);

is(
    Class::Veyra::SourceDiff->unified(
        'example.veyra',
        "class App::Main {\nact message {\n}\n}\n",
        "class App::Main {\n    act message {\n    }\n}\n",
    ),
    <<'DIFF',
--- a/example.veyra
+++ b/example.veyra
@@ -1,4 +1,4 @@
 class App::Main {
-act message {
-}
+    act message {
+    }
 }
DIFF
    'makes indentation changes visible',
);

done_testing;

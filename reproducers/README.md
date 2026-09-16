orafce_mail reproducers
=======================

One script per issue found in the review (see `../REVIEW.md`).  Each one
demonstrates the problem against a real server and a real SMTP conversation,
and each one exits

  * `1`  while the issue is present,
  * `0`  once it is fixed,
  * `77` if it could not be run at all (no compiler, no database, ...).

So `run_all.sh` reproduces the issues before the fixes and is a regression
test after them.


Nothing here needs a superuser
------------------------------

The only privileged step is creating the extension and the roles, which is
what an administrator would do anyway.  `setup.sql` does that once:

    psql -U postgres -f setup.sql

It creates two login roles:

  * `orafce_mail_user`   - a member of `orafce_mail`, `orafce_mail_config_url`
                           and `orafce_mail_config_userpwd`, which is the most
                           privileged an ordinary user can be here;
  * `orafce_mail_nobody` - a member of none of them.

Every reproducer then runs as one of those two.  They refuse to run as a
superuser, so a result can never be explained away as "well, you were
superuser".


Running them
------------

    cd reproducers
    ./run_all.sh              # summary
    ./run_all.sh -v           # full output
    ./02_crlf_injection.sh    # one of them

Connection details come from the usual libpq environment variables:

    export PGHOST=/tmp PGPORT=5432 PGDATABASE=postgres

and two more of our own:

    export SMTP_PORT=52525    # free port for the capture SMTP server
    export REPRO_USER=orafce_mail_user
    export REPRO_NOBODY=orafce_mail_nobody


How the mail is inspected
-------------------------

`smtp_sink.py` is a capture SMTP server: it answers just enough for libcurl to
hand over a message, and logs the whole conversation.  Commands it received
are prefixed with `C: ` and the contents of `DATA` are logged verbatim, which
is what lets a reproducer tell a header the extension meant to send from an
SMTP command it was tricked into sending.

Two of the scripts need no database at all:

  * `08_build_libcurl_below_7_39.sh` only compiles `orafce_mail.c`;
  * `09_read_callback_truncation.sh` extracts the buffer handling from
    `orafce_mail.c` by name and drives it directly, under
    `-fsanitize=address,undefined` when the compiler has it.

`01b_postmaster_segfault.sh` creates a throwaway cluster with `initdb` in a
temporary directory; it does not touch the cluster the other scripts use.

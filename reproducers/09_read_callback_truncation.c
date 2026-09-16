/*
 * Issue 09 - read_callback() reports end of data when it merely runs out of room
 *
 * In the line-ending conversion path a lone "\n" has to be written as two
 * bytes.  When only one byte of the buffer libcurl offered is left the loop
 * breaks, and if that happens before anything at all has been written the
 * function returns 0.  For a CURLOPT_READFUNCTION - which is what this is -
 * 0 means "end of data", so the message is silently cut short at that point
 * instead of being continued in the next call.
 *
 * libcurl is entitled to ask for any number of bytes from one upwards.  This
 * driver asks for exactly what libcurl is allowed to ask for and compares the
 * bytes that come back with the conversion the function is supposed to
 * perform.
 *
 * Built and run by 09_read_callback_truncation.sh, which extracts the
 * functions under test out of orafce_mail.c so that this cannot drift away
 * from the code it is testing.
 */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef long long curl_off_t;
#define CURL_SEEKFUNC_OK 0
#define CURL_SEEKFUNC_FAIL 1

struct curl_slist { char *data; struct curl_slist *next; };

static void *palloc(size_t n) { void *p = malloc(n); assert(p); return p; }
static void *repalloc(void *p, size_t n) { void *q = realloc(p, n); assert(q); return q; }
static void pfree(void *p) { free(p); }
static char *
pnstrdup(const char *s, size_t n)
{
	char	   *r = malloc(n + 1);

	assert(r);
	memcpy(r, s, n);
	r[n] = '\0';
	return r;
}
static struct curl_slist *
curl_slist_append(struct curl_slist *sl, const char *s)
{
	struct curl_slist *node = malloc(sizeof(*node));
	struct curl_slist **pp = &sl;

	assert(node);
	node->data = strdup(s);
	node->next = NULL;
	while (*pp)
		pp = &(*pp)->next;
	*pp = node;
	return sl;
}
static void
curl_slist_free_all(struct curl_slist *sl)
{
	while (sl)
	{
		struct curl_slist *next = sl->next;

		free(sl->data);
		free(sl);
		sl = next;
	}
}
#define elog(level, ...) do { fprintf(stderr, "elog: " __VA_ARGS__); abort(); } while (0)
#define ERROR 1
#define Assert(x) assert(x)

#include "extracted.inc"

/* ---------------------------------------------------------------- */

/* what the conversion is supposed to produce */
static char *
expected(const char *body, size_t bodylen, size_t *outlen)
{
	char	   *out = malloc(2 * bodylen + 1);
	size_t		n = 0,
				i;

	for (i = 0; i < bodylen;)
	{
		if (i + 1 < bodylen && body[i] == '\r' && body[i + 1] == '\n')
		{
			out[n++] = '\r';
			out[n++] = '\n';
			i += 2;
		}
		else if (body[i] == '\n')
		{
			out[n++] = '\r';
			out[n++] = '\n';
			i += 1;
		}
		else
			out[n++] = body[i++];
	}
	*outlen = n;
	return out;
}

/*
 * Drain the reader the way libcurl does, handing it buffers of exactly
 * "chunk" bytes.  The buffer is allocated at exactly that size so that a
 * sanitizer build also catches a write past its end.
 */
static char *
drain(const char *body, size_t bodylen, size_t chunk, size_t *outlen)
{
	BinaryReader reader;
	char	   *got = malloc(2 * bodylen + 64);
	size_t		gotlen = 0;
	size_t		guard = 0;

	memset(&reader, 0, sizeof(reader));
	reader.data = (char *) body;
	reader.size = bodylen;
	reader.unix2dos_nl = true;

	for (;;)
	{
		char	   *buf = malloc(chunk);
		size_t		n = read_callback(buf, 1, chunk, &reader);

		assert(n <= chunk);
		if (n == 0)
		{
			free(buf);
			break;
		}
		memcpy(got + gotlen, buf, n);
		gotlen += n;
		free(buf);

		if (++guard > 1000000)
		{
			fprintf(stderr, "read_callback() never reported end of data\n");
			abort();
		}
	}

	*outlen = gotlen;
	return got;
}

static void
show(const char *label, const char *s, size_t n)
{
	size_t		i;

	printf("    %-9s \"", label);
	for (i = 0; i < n && i < 40; i++)
	{
		if (s[i] == '\r')
			printf("\\r");
		else if (s[i] == '\n')
			printf("\\n");
		else
			putchar(s[i]);
	}
	printf("%s\" (%zu bytes)\n", n > 40 ? "..." : "", n);
}

int
main(void)
{
	static const char body[] = "one\ntwo\nthree\nfour\n";
	static const size_t chunks[] = {1, 2, 3, 7, 64};
	const size_t bodylen = sizeof(body) - 1;
	size_t		explen;
	char	   *exp = expected(body, bodylen, &explen);
	int			failed = 0;
	size_t		c;

	printf("body to send:\n");
	show("input", body, bodylen);
	show("expected", exp, explen);
	printf("\nwhat read_callback() produces for each buffer size libcurl may offer:\n");

	for (c = 0; c < sizeof(chunks) / sizeof(chunks[0]); c++)
	{
		size_t		gotlen;
		char	   *got = drain(body, bodylen, chunks[c], &gotlen);
		bool		bad = (gotlen != explen || memcmp(got, exp, explen) != 0);

		printf("\n  buffer size %zu: %s\n", chunks[c], bad ? "TRUNCATED" : "ok");
		show("produced", got, gotlen);
		if (bad)
			failed = 1;
		free(got);
	}

	free(exp);

	if (failed)
	{
		printf("\nBUG REPRODUCED: read_callback() returned 0 - which libcurl reads as\n");
		printf("end of data - while it still had bytes to deliver, so the message\n");
		printf("was cut short.\n");
		return 1;
	}

	printf("\nNOT REPRODUCED (looks fixed): every buffer size produced the whole message.\n");
	return 0;
}

"""The verdict about a page, decided once for both engines.

Both engines scanned the same four lists from `detection.py` in the same order
and reached the same verdict, in code written twice. The lists were shared; the
rule that reads them was not, which is the shape that lets two engines drift
while looking like they agree.

Like `assembly.py`, and for the same reason (one engine is synchronous and the
other asynchronous), the rule is a generator: it says what to look at and in
what order, and each engine supplies only how to look. Short-circuiting matters
here and is preserved: the stealth engine re-runs this every poll while a
challenge is up, and each selector costs a round trip to the browser.

The one difference between the engines is a parameter rather than a fork.
`turnstile_is_a_challenge` is false for the Chrome engine, which can only reach
a checkbox through a tab count the caller supplies as `tabs_till_verify`, so
treating a bare widget as a challenge would send it into a wait loop it cannot
win and cost the whole budget. The stealth engine clicks by coordinate and needs
no such help. That is a capability boundary, pinned by
`test_engine_conformance.DetectionConformanceTest`.
"""
import logging
from enum import Enum, auto

from detection import (ACCESS_DENIED_SELECTORS, ACCESS_DENIED_TITLES,
                       CHALLENGE_SELECTORS, CHALLENGE_TITLES, TURNSTILE_SELECTORS)

BLOCKED_MESSAGE = ('Cloudflare has blocked this request. '
                   'Probably your IP is banned for this site, check in your web browser.')


class Step(Enum):
    """Something only the engine can do. The order they appear in is the rule."""
    NAVIGATE = auto()
    SET_COOKIES = auto()   # carries the cookies the caller supplied
    SETTLE = auto()        # wait, bounded, for the page to stop loading and moving


class Look(Enum):
    """Something only the engine can see. The order they appear in is the rule."""
    TITLE = auto()
    SELECTOR = auto()   # carries the selector to test, answers True or False


class Verdict(Enum):
    DENIED = auto()
    CHALLENGE = auto()
    NONE = auto()


def approach(req):
    """Load the page, with any cookies the caller supplied applied to it.

    Cookies force a second navigation. They can only be set against an origin,
    so the browser has to be on the page before they can go in, and the document
    it fetched to get there was fetched without them. Skipping the reload leaves
    the caller's cookies set but unused, which looks like they were ignored.

    Driven by `run` or `run_async` below rather than called directly.
    """
    yield Step.NAVIGATE, None
    if req.cookies:
        logging.debug("Setting cookies...")
        yield Step.SET_COOKIES, req.cookies
        yield Step.NAVIGATE, None


def verdict(*, turnstile_is_a_challenge: bool):
    """Yield each look in the order it must happen, and decide from the answers.

    Returns (verdict, is_turnstile, reason), where reason names the title or
    selector that decided it, for the log line.

    Driven by `run` or `run_async` below rather than called directly.
    """
    title = yield Look.TITLE, None

    for denied in ACCESS_DENIED_TITLES:
        if title.startswith(denied):
            return Verdict.DENIED, False, denied
    for selector in ACCESS_DENIED_SELECTORS:
        if (yield Look.SELECTOR, selector):
            return Verdict.DENIED, False, selector

    # Only looked for by an engine that could act on one. Chrome cannot reach a
    # checkbox without a tab count from the caller, so asking would cost a round
    # trip per detection for an answer it has no use for.
    is_turnstile = False
    if turnstile_is_a_challenge:
        for selector in TURNSTILE_SELECTORS:
            if (yield Look.SELECTOR, selector):
                return Verdict.CHALLENGE, True, selector

    for challenge in CHALLENGE_TITLES:
        if challenge.lower() == title.lower():
            return Verdict.CHALLENGE, is_turnstile, title
    for selector in CHALLENGE_SELECTORS:
        if (yield Look.SELECTOR, selector):
            return Verdict.CHALLENGE, is_turnstile, selector

    return Verdict.NONE, is_turnstile, None


def settled_verdict(*, turnstile_is_a_challenge: bool):
    """`verdict`, taken a second time after the page settles if the first finds
    nothing.

    A clean first look is not yet the page the client should get. A challenge
    or widget injected after load is not in the DOM yet, and a site's own
    script guard redirects once its check runs, so the document read at load
    is the guard and not the page it was guarding. Only a clean look waits:
    a challenge is already being acted on.

    Driven by `run` or `run_async` below rather than called directly.
    """
    found = yield from verdict(turnstile_is_a_challenge=turnstile_is_a_challenge)
    if found[0] is Verdict.NONE:
        yield Step.SETTLE, None
        found = yield from verdict(turnstile_is_a_challenge=turnstile_is_a_challenge)
    return found


def run(handlers: dict, kernel=None, **kwargs):
    """Drive a kernel where every step is synchronous."""
    generator = (kernel or verdict)(**kwargs)
    try:
        step, arg = next(generator)
        while True:
            step, arg = generator.send(handlers[step](arg))
    except StopIteration as done:
        return done.value


async def run_async(handlers: dict, kernel=None, **kwargs):
    """Drive the same kernel where every step is awaitable."""
    generator = (kernel or verdict)(**kwargs)
    try:
        step, arg = next(generator)
        while True:
            step, arg = generator.send(await handlers[step](arg))
    except StopIteration as done:
        return done.value

// Tests for MenuIndex.js, the searchable index behind the overview's command
// menu results. Run with: node --test tests/
//
// MenuIndex.js is plain JS with no QML dependencies, so it loads directly under
// Node. The fixtures are kept in-repo rather than read from $OMARCHY_PATH, so
// the suite runs anywhere -- including CI, where Omarchy is not installed.
//
// The QML around it (MenuSearch, OverviewSearch) is out of scope here; that
// would need qmltestrunner.

const { test, describe } = require("node:test");
const assert = require("node:assert");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const M = require("../MenuIndex.js");
const FIXTURES = path.join(__dirname, "fixtures");

const readFixture = name => fs.readFileSync(path.join(FIXTURES, name), "utf8");
const defaultItems = () => M.parseMenuJsonc(readFixture("menu.jsonc"));
const userItems = () => M.parseMenuJsonc(readFixture("user-menu.jsonc"));
const merged = () => M.mergeMenuSources(defaultItems(), userItems());

describe("stripJsonc", () => {
    test("drops whole-line comments and trailing commas", () => {
        const raw = `{
  // a comment
  "a": {"label":"A"},
}`;
        assert.deepStrictEqual(JSON.parse(M.stripJsonc(raw)), { a: { label: "A" } });
    });

    test("leaves a // inside a string alone", () => {
        const raw = '{"a":{"target":"https://omarchy.org"}}';
        assert.strictEqual(JSON.parse(M.stripJsonc(raw)).a.target, "https://omarchy.org");
    });
});

describe("parseMenuJsonc", () => {
    test("infers kind from the fields present", () => {
        const byId = {};
        for (const entry of defaultItems())
            byId[entry.id] = entry;
        assert.strictEqual(byId["system.lock"].kind, "action", "action field -> action");
        assert.strictEqual(byId["learn.docs"].kind, "link", "target field -> link");
        assert.strictEqual(byId["learn"].kind, "menu", "neither -> menu");
    });

    test("derives the parent from the dotted id", () => {
        const byId = {};
        for (const entry of defaultItems())
            byId[entry.id] = entry;
        assert.strictEqual(byId["system.lock"].parent, "system");
        assert.strictEqual(byId["system"].parent, "root");
    });

    test("returns an empty list for malformed input rather than throwing", () => {
        assert.deepStrictEqual(M.parseMenuJsonc("{ not json"), []);
        assert.deepStrictEqual(M.parseMenuJsonc(""), []);
        assert.deepStrictEqual(M.parseMenuJsonc(null), []);
    });
});

describe("mergeMenuSources", () => {
    test("the user file overrides a default entry by id", () => {
        const { items } = merged();
        assert.strictEqual(items["style.theme"].label, "Colour theme");
        assert.strictEqual(items["style.theme"].action, "my-theme-switcher");
    });

    test("keeps entries only the user defines", () => {
        assert.strictEqual(merged().items["custom.note"].label, "Note");
    });

    test("an overridden id is not duplicated in the order", () => {
        const { itemOrder } = merged();
        assert.strictEqual(itemOrder.filter(id => id === "style.theme").length, 1);
    });

    // Regression: order used to be stamped onto the caller's objects. Those live
    // in QML `var` properties, where an in-place write can be dropped, which
    // would collapse searchScore's declaration-order tiebreak.
    test("does not mutate the arrays it is given", () => {
        const d = defaultItems();
        const before = d.map(e => e.order);
        M.mergeMenuSources(d, []);
        assert.deepStrictEqual(d.map(e => e.order), before);
    });

    // Worth pinning down because it surprises people writing an override: every
    // field is normalised, so a partial override blanks the ones it omits. Same
    // behaviour as Omarchy's own MenuModel.js.
    test("a partial override blanks the fields it does not declare", () => {
        const { items } = merged();
        const fromDefault = defaultItems().find(e => e.id === "style.theme");
        assert.strictEqual(fromDefault.description, "change the colour scheme");
        assert.strictEqual(items["style.theme"].description, "",
            "the user entry omits description, so the merged entry loses it");
    });

    test("skips entries without an id", () => {
        const { itemOrder } = M.mergeMenuSources([null, { label: "x" }], []);
        assert.deepStrictEqual(itemOrder, []);
    });
});

describe("matchesQuery", () => {
    const find = id => merged().items[id];

    test("matches on the label", () => {
        assert.ok(M.matchesQuery(find("system.lock"), "lock"));
    });

    test("matches on an alias", () => {
        assert.ok(M.matchesQuery(find("install.docker"), "container runtime"));
    });

    test("matches a whole word of the description", () => {
        // setup.dns is not overridden, so it keeps its description. Its label is
        // "DNS", so "resolver" can only be matching the description.
        assert.ok(M.matchesQuery(find("setup.dns"), "resolver"));
    });

    // A bare substring of the description must not match, or "in" would drag in
    // everything that says "install".
    test("does not match a partial word of the description", () => {
        assert.ok(!M.matchesQuery(find("setup.dns"), "esolver"));
    });

    test("requires every term to match", () => {
        assert.ok(!M.matchesQuery(find("system.lock"), "lock nonsense"));
    });

    test("never matches the synthetic root", () => {
        assert.ok(!M.matchesQuery({ id: "root", label: "root" }, "root"));
    });
});

describe("searchScore", () => {
    const { items } = merged();
    const score = id => M.searchScore(items, items[id], "theme");

    test("an exact label beats a partial one", () => {
        const exact = M.searchScore(items, items["system.lock"], "lock");
        const partial = M.searchScore(items, items["style.theme"], "theme");
        assert.ok(exact < partial, `exact ${exact} should sort before partial ${partial}`);
    });

    test("a prefix match beats a description-only match", () => {
        const prefix = M.searchScore(items, items["install.docker"], "dock");
        const desc = M.searchScore(items, items["setup.dns"], "resolver");
        assert.ok(prefix < desc, `prefix ${prefix} should sort before description ${desc}`);
    });

    test("is stable for the same input", () => {
        assert.strictEqual(score("style.theme"), score("style.theme"));
    });
});

describe("pathFor / parentPathFor", () => {
    const { items } = merged();

    test("builds a breadcrumb from the ancestors", () => {
        assert.strictEqual(M.pathFor(items, "system.lock"), "System › Lock");
        assert.strictEqual(M.parentPathFor(items, "system.lock"), "System");
    });

    test("a top-level entry has no parent path", () => {
        assert.strictEqual(M.parentPathFor(items, "system"), "");
    });
});

describe("shellQuote", () => {
    test("wraps a plain value", () => {
        assert.strictEqual(M.shellQuote("plain"), "'plain'");
    });

    test("neutralises a glob so bash cannot expand it", () => {
        assert.strictEqual(M.shellQuote("opt*"), "'opt*'");
    });

    test("escapes an embedded single quote", () => {
        assert.strictEqual(M.shellQuote("it's"), "'it'\\''s'");
    });

    test("treats null and undefined as empty", () => {
        assert.strictEqual(M.shellQuote(null), "''");
        assert.strictEqual(M.shellQuote(undefined), "''");
    });
});

describe("guardScript", () => {
    const scriptFor = extra => {
        const { items } = merged();
        Object.assign(items, extra || {});
        return M.guardScript(items);
    };

    test("emits one branch per guarded entry and none for the rest", () => {
        const script = scriptFor();
        assert.match(script, /system\.suspend:w:1/);
        assert.match(script, /system\.hibernate:w:1/);
        // system.lock has no `when`, so it must not be probed at all.
        assert.doesNotMatch(script, /system\.lock:w/);
    });

    test("uses printf with a quoted payload rather than echo", () => {
        const script = scriptFor();
        assert.match(script, /printf '%s\\n' '/);
        assert.doesNotMatch(script, /then echo [^']/);
    });

    // An unquoted echo would expand this against the working directory, emitting
    // one line per matching file and desynchronising the whole batch.
    test("quotes an id containing a glob character", () => {
        const script = scriptFor({ "opt*": { id: "opt*", when: "true" } });
        assert.ok(script.includes("'opt*:w:1'"), "glob id should be quoted verbatim");
    });

    // The reply is split on the last two colons, so such an id could not be read
    // back. Skipping it leaves one row unanswered instead of corrupting the rest.
    test("skips ids that would break the reply format", () => {
        const script = scriptFor({
            "bad:id": { id: "bad:id", when: "true" },
            "bad\nid": { id: "bad\nid", when: "true" }
        });
        assert.doesNotMatch(script, /bad:id/);
        assert.doesNotMatch(script, /bad\nid/);
    });

    test("returns an empty string when nothing is guarded", () => {
        assert.strictEqual(M.guardScript({ a: { id: "a", label: "A" } }), "");
        assert.strictEqual(M.guardScript(null), "");
    });
});

describe("guardScript + parseGuardReply round trip", () => {
    test("a real bash run resolves each guard to its condition", () => {
        const { items } = merged();
        const out = execFileSync("bash", ["-c", M.guardScript(items)], { encoding: "utf8" });
        const results = M.parseGuardReply(out);
        assert.strictEqual(results["system.suspend"], true, "`when: true` should pass");
        assert.strictEqual(results["system.hibernate"], false, "`when: false` should fail");
        assert.ok(!("system.lock" in results), "an unguarded entry gets no answer");
    });

    test("a glob id survives the round trip intact", () => {
        const items = { "opt*": { id: "opt*", when: "true" } };
        const out = execFileSync("bash", ["-c", M.guardScript(items)], { encoding: "utf8" });
        assert.deepStrictEqual(M.parseGuardReply(out), { "opt*": true });
    });
});

describe("parseGuardReply", () => {
    test("splits from the right so dotted ids survive", () => {
        assert.deepStrictEqual(
            M.parseGuardReply("a.b.c:w:1\nd.e:w:0\n"),
            { "a.b.c": true, "d.e": false });
    });

    test("ignores the checked tag", () => {
        assert.deepStrictEqual(M.parseGuardReply("a:c:1\nb:w:1\n"), { b: true });
    });

    test("skips blank and malformed lines", () => {
        assert.deepStrictEqual(M.parseGuardReply("\n\nnocolons\na:w:1\n  \n"), { a: true });
    });

    test("treats anything but 1 as false", () => {
        assert.deepStrictEqual(M.parseGuardReply("a:w:0\nb:w:\nc:w:x\n"),
            { a: false, b: false, c: false });
    });

    test("returns an empty object for empty input", () => {
        assert.deepStrictEqual(M.parseGuardReply(""), {});
        assert.deepStrictEqual(M.parseGuardReply(null), {});
    });
});

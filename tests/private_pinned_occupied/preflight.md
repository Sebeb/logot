# Source preflight correction

No Godot parser, engine, import, browser, export or runtime gate has run. This source audit corrects the invalid rect_changed wiring and the suppressed registry-test premise from source-only commit e789f3656cb27d0ca945c0b5a5276490e84d4ef4. That Git object and /private/tmp/logot-pinned-occupied-source-03 remain unchanged. Engine acceptance remains HELD.

Every newly connected engine signal was checked against its actual declaring class API. All have zero arguments and use zero-argument callbacks. Geometry wiring uses a typed Array[Signal] of direct properties, so an invalid property cannot be silently skipped. Existing-connection checks prevent duplicate subscriptions; no has_signal guard masks geometry wiring.

| Signal | Declaring class and official API |
| --- | --- |
| item_rect_changed | [CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-signal-item-rect-changed) |
| visibility_changed | [CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-signal-visibility-changed) |
| minimum_size_changed | [Control](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-signal-minimum-size-changed) |
| tree_entered | [Node](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-signal-tree-entered) |
| tree_exiting | [Node](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-signal-tree-exiting) |
| sort_children | [Container](https://docs.godotengine.org/en/stable/classes/class_container.html#class-container-signal-sort-children) |
| process_frame | [SceneTree](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-signal-process-frame) |
| pinned_overlay_occupied_rects_changed | Declared directly, no arguments, on LogotDisplay and Console in this change |

The dynamic baseline guard checks only whether the public capability exists before invoking it. It intentionally collects two assertion failures rather than calling missing methods. Dynamically loaded scripts, displays, Console and case objects use untyped assignment with `=`, not inference from unknown dynamic return types. Geometry operations whose result types matter explicitly declare Rect2, Transform2D, Control, Vector2, Dictionary or PackedVector2Array. Typed getters return Dictionary[String, Rect2]; all dictionary entries are Rect2 values, copied before publication to callers. This is a source-level type/inference review, not a claim that the Godot parser has accepted the files.

The terminal fixture sequence now restores an occupied old pin before replacement, asserts that premise, and asserts that suppression produces empty geometry while the disconnected Console gets no forwarding. Teardown preserves the suppression assertion. After re-entry the real registry test explicitly unsuppresses the display, restores user visibility, and asserts effective visibility, tree membership and viewport ownership before real Console registration. Real registry removal still must return empty geometry. External registration then proves Console cannot fall back to that display; bindings are disconnected, Console is freed, both owned SubViewports are queued for deletion, and teardown frames are awaited.

The new collection is exactly two baseline failures and 59 candidate checks. The unchanged earlier 291-check evidence validates only its earlier implementation. Standard engine path remains /opt/homebrew/bin/godot; each planned OS proof verifies its 4.7.2 banner without invoking a suffix binary.

Full gate ownership stays inside the proposed 350-second exclusive slot. Engine process limits total 292 seconds, boundary preflight is bounded at 10 seconds, and 30 seconds are reserved for cleanup/postflight. The owner preserves exact-token inventories and logs, removes only fresh tokens proved by successful OS proofs, checks canonical cache/icon/normal-userdata boundaries, verifies frozen source bytes, and records completion before the deadline. A failed proof cannot authorize deletion of an unproved token; any such remnant is a reported cleanup failure and blocks acceptance. No cleanup or snapshot operation has run during source preparation.

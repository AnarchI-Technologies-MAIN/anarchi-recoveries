# Kiln destructive-proof boundary

Status: Step 41 pure specimen harness

`tools/kiln/kiln_protocol.py` implements the four proof stages from SPEC-1.6:

1. create a deep-copied specimen with a source digest;
2. mutate a named field without mutating the source;
3. prove the mutation fractured the digest and required fields survived;
4. prove restoration by comparing a restored digest to the source digest.

Kiln authority is explicitly forbidden for repair, promotion, commit, push,
publication, deployment, and authorization. The harness does not call a
service, alter production, or write back to the specimen. Promotion remains a
separate human/governance decision after the proof artifact exists.

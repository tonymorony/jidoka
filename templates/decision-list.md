<!-- How a set of choices goes to the owner. The orchestrator fills it. Form A is a numbered list for choices that can wait. Form B is one interactive question for a choice that blocks. -->
# Decisions for the owner, <date>

## Form A: the numbered list

Use it when the choices can wait: at the end of a run, in a pull request body, or when the owner said not to interrupt.

Answer by number, for example "1 ok, 2 b, 3 ok". "ok" takes the recommended option.

**1. <the choice, as one question>**

- Today: <what the product or the project does now, as verified: a file, a test or an output>.
- a. <the recommended option> (recommended): <one sentence of reason>.
- b. <another option>: <what it costs or risks>.
- With no answer: <what the orchestrator does, and what waits>.

**2. <the choice, as one question>**

- Today: <...>.
- a. <the recommended option> (recommended): <...>.
- b. <another option>: <...>.
- With no answer: <...>.

Rules for the list:

1. One item is one choice. Split an item that holds two.
2. The first line of an item says what is true today, as verified. The owner decides on that premise.
3. The recommended option comes first. Each option is short and concrete.
4. Each item says what happens with no answer. No answer never allows an act that the rules keep for the owner.
5. Keep the list short enough for one answer in one message. Send no gallery of states with it.
6. For a choice about a screen, show the pictures the way the project instruction file says (D-8). A link is private and sits on a host that the owner named there. With no such host, give the path of the file and send nothing to any host. Ask after the owner says "seen".

After the answer:

1. Write each answer under its number in the state file, with the time, and on its ticket. Add one line for it to the decision log (O-6).
2. When an "ok" can cover two things, take the narrow reading and say how you read it before you act: "I read '2 ok' as <reading>. It does not cover <the other thing>."
3. Start the work that each answer allows. Say what you started and what you hold back.

## Form B: one interactive question

Use it when a choice blocks the work now and the owner is present. One question for each call of the question tool.

- **Count:** "Decision <N> of <M>".
- **Context:** one short paragraph. Its first sentence says what is true today, as verified.
- **Question:** <one question, one choice>.
- **Options:** <the recommended option, with its reason in a few words>, then <another option>, then <another option>. Two to four options.
- **After the answer:** write it on the ticket and in the state file, then ask the next question.

Rules for the question:

1. Never put two questions into one call.
2. When the owner said not to interrupt, ask nothing. The choice goes into Form A, and the work goes on with all that does not depend on it.
3. A question does not replace a check. Find the facts yourself; ask only for what the owner alone decides.

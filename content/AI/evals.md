---
title: Evaluating LLM Systems
tags: [ai, evals, llm, testing, quality]
date: 2026-10-10
description: How to measure whether an LLM application works — building a dataset, code-based, model-based and human graders, offline and online evaluation, metrics for RAG and agents, handling non-determinism, and running evals in CI.
---

# Evaluating LLM Systems

Changing a prompt, a model or a retrieval setting improves some outputs and breaks others. Without measurement, you learn which only from users. An **eval** is a repeatable test of an LLM system's behaviour: a set of inputs, a way to run the system on them, and a way to score the results.

Evals are to LLM applications what tests are to code, with one difference: outputs are non-deterministic and often open-ended, so scoring is harder than an equality check. Most of the craft is in the scoring.

## Start by reading outputs

Before any tooling, look at real inputs and outputs — a hundred of them. Write a note on each failure and group the notes. The groups are your **failure modes**, and they tell you what to measure. Teams that skip this step build elaborate metrics for problems they do not have and miss the ones they do.

Two generic metrics that sound useful — "helpfulness", "quality" on a 1–5 scale — rarely discriminate. Specific, binary checks derived from observed failures do: "cites a source for every factual claim", "does not promise a refund", "asks for the order number when it is missing".

## Anatomy of an eval

```
dataset ──► system under test ──► outputs ──► graders ──► scores ──► aggregate + compare to baseline
(inputs, optional        (prompt + model +              (code, model,
 expected outputs)        retrieval + tools)             or human)
```

## The dataset

| Source                     | Value                                                                    |
| :------------------------- | :----------------------------------------------------------------------- |
| Real production inputs     | The actual distribution — the most valuable source once you have traffic |
| Observed failures          | Regression tests: every bug becomes a case                               |
| Hand-written cases         | Cover known edge cases and policies before launch                        |
| Synthetic, model-generated | Breadth quickly; review them, and vary personas, intents and difficulty  |
| Adversarial                | Injection attempts, out-of-scope requests, ambiguous or hostile input    |

Guidelines:

- **Start small.** Twenty to fifty carefully chosen cases produce real signal. Grow it from failures.
- **Balance it.** Include cases where the right behaviour is to refuse, to ask a clarifying question, or to say "I don't know" — otherwise you optimise for always answering.
- **Keep a held-out set** that you do not tune prompts against, or you will overfit to your own tests.
- **Version it** alongside the code and prompts.
- **Unambiguous cases.** If two experts would disagree on the right answer, the case measures noise.

## Graders

| Grader                           | How                                                                                                                                            | Strengths                         | Weaknesses                                               |
| :------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------- | :------------------------------------------------------- |
| **Code-based**                   | Exact or regex match, JSON schema validation, required or forbidden strings, executing generated code against tests, checking a database state | Fast, cheap, deterministic        | Brittle for free text; cannot judge nuance               |
| **Model-based** ("LLM as judge") | Another model scores the output against a rubric                                                                                               | Handles open-ended text; scalable | Costs money; non-deterministic; must itself be validated |
| **Human**                        | Experts review outputs                                                                                                                         | The ground truth                  | Slow, expensive, inconsistent between raters             |

Use the cheapest grader that is reliable for the property. Many checks need no model at all: valid JSON, correct tool called, a number within tolerance, no PII in the output.

### Making a model judge trustworthy

A judge is another LLM component and needs its own evaluation.

1. **One criterion per judge.** A prompt that scores accuracy, tone and completeness at once does each badly.
2. **Binary or small categorical outputs**, not 1–10 scales. "Pass or fail, with a reason" is far more consistent.
3. **Ask for reasoning before the verdict.** It improves accuracy and makes disagreements debuggable.
4. **Give the rubric and examples** of passes and fails, taken from real data.
5. **Validate against human labels.** Have a person label a sample, then measure the judge's agreement — separately on the pass and the fail class, since failures are usually rare. Iterate on the judge prompt until agreement is acceptable.
6. **Re-check after changing the judge model.** Its behaviour shifts too.

Known biases: judges favour longer answers, their own model family's style, and the first option in a pairwise comparison (randomise the order).

## Offline and online

|         | Offline                               | Online                                                              |
| :------ | :------------------------------------ | :------------------------------------------------------------------ |
| When    | Before release, in development and CI | In production, continuously                                         |
| Data    | A fixed dataset                       | Live traffic                                                        |
| Purpose | Catch regressions; compare candidates | Detect drift and problems the dataset did not anticipate            |
| Signals | Grader scores                         | Sampled grading, explicit feedback, implicit behaviour, A/B results |

Online signals worth capturing: thumbs up and down, whether the user rephrased or retried, whether they copied the answer, escalation to a human, task completion. Feed interesting production traces back into the offline dataset — that loop is what keeps evals honest.

## Metrics by system type

**Classification and extraction.** Precision, recall and F1 against labelled data; exact match per field.

**Retrieval-augmented generation.** Evaluate the two halves separately, because they fail differently:

| Stage      | Metric                | Question                                           |
| :--------- | :-------------------- | :------------------------------------------------- |
| Retrieval  | Recall@k, precision@k | Were the relevant documents among the top k?       |
| Retrieval  | MRR, nDCG             | Were they ranked near the top?                     |
| Generation | **Faithfulness**      | Is every claim supported by the retrieved context? |
| Generation | Answer relevance      | Does it address the question that was asked?       |
| End to end | Correctness           | Does it match the reference answer?                |

A wrong answer with the right documents retrieved is a generation problem; a wrong answer with the wrong documents is a retrieval problem. Details in [[AI/rag|RAG architecture]] and [[AI/rag-in-production|RAG in production]].

**Agents.** Score the outcome first — did the environment end in the right state? — then the trajectory: correct tools, sensible order, no forbidden actions, within the step and cost budget. See [[AI/agents|agents]].

**Safety and policy.** Refusal on disallowed requests, _and_ non-refusal on legitimate ones; resistance to [[AI/prompt-injection|prompt injection]]; no leakage of system prompts or personal data.

**Always track** latency, tokens and cost per request alongside quality. A change that improves quality by a point and doubles cost is a decision, not a win.

## Non-determinism

- **Run each case several times** and report a pass rate, not a single result. For agents this is essential.
- **Do not trust small differences.** With fifty cases, a move from 82% to 86% is two cases and well inside the noise. Use confidence intervals, or a paired comparison on the same cases.
- **Look at what changed**, not only the aggregate: which cases flipped from pass to fail?
- Lowering temperature reduces variance but does not remove it, and is not available on every model.

## In the development loop

```
change prompt / model / retrieval
        │
        ▼
run the eval suite ──► compare with the baseline, case by case
        │
   regressions? ──yes──► inspect the failing cases, fix, repeat
        │ no
        ▼
merge ──► deploy to a small share of traffic ──► watch online signals ──► roll out
```

- **In CI**, run a fast subset on every pull request and the full suite before release, with a threshold that fails the build — see [[DevOps/ci-cd/pipeline-design|pipeline design]].
- **Pin model versions.** A provider updating an alias changes behaviour with no change on your side; an eval run on a schedule detects it.
- **Treat prompts as code**: versioned, reviewed, tested.
- **Record everything**: dataset version, prompt version, model, parameters and scores, so any result can be reproduced.

## Tooling

Frameworks such as Promptfoo, Inspect, DeepEval, Ragas, Braintrust, LangSmith and Phoenix provide datasets, graders, experiment tracking and trace viewers. They save time, but none removes the need to define what "good" means for your application. A spreadsheet and a script are a legitimate starting point.

## Common mistakes

| Mistake                                       | Consequence                                                 |
| :-------------------------------------------- | :---------------------------------------------------------- |
| No evals; judging by a few manual tries       | Regressions ship; nobody can tell if a change helped        |
| Generic metrics not tied to observed failures | Scores move without quality moving                          |
| An unvalidated model judge                    | Confident numbers that do not track human judgement         |
| Tuning against the whole dataset              | Overfitting; production disappoints                         |
| Only "happy path" cases                       | The system is never tested where it actually fails          |
| Aggregates only                               | Regressions in an important slice hidden by gains elsewhere |
| Offline only                                  | Blind to drift and to real usage                            |

## Related

- [[AI|AI hub]]
- [[AI/langchain/10-testing|Testing LangChain]] and [[AI/langgraph/12-testing|testing LangGraph]]
- [[AI/prompt-engineering|Prompt engineering]]
- [[AI/mlops|MLOps]] — the wider lifecycle
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/README|Testing strategies]] — the classical counterpart

## Across the wiki

- [[Kubernetes/guides/delivery/templating-patching/helm/testing|Helm Chart Testing]] — testing (Kubernetes)
- [[Architecture/solution-architecture-concepts/software-engineering-concepts/testing/unit-testing|Unit Testing Principles & Test-Driven Development (TDD)]] — testing (Architecture)

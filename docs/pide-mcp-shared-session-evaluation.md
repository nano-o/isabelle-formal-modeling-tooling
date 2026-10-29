# PIDE MCP for multiple agents sharing one session

Recorded 2026-10-29 from the 2026-10-27 comparison. Status: proposed pilot.

PIDE MCP is worth evaluating for several autonomous agents developing
different theories in one resident Isabelle session. The potential benefit
is sharing the loaded common development while agents independently submit
edits and PIDE checks independent work asynchronously. This could reduce
memory use and repeated checking compared with one ic2 prover per worktree.
The benefit needs measurement before changing the default workflow.

## Comparison with ic2

Both systems already use persistent headless PIDE sessions. Our ic2 also
checks incrementally, retaining unchanged document prefixes, and exposes
optional MCP tools. The relevant difference is how agents submit work:

- ic2 has one server-wide check slot. A second submission is refused while
  a check is running. One check can contain multiple theories, but agents
  cannot independently submit overlapping check jobs.
- PIDE MCP dispatches tool calls as separate tasks. Document mutations use
  a session lock, but that lock does not cover the entire proof-checking
  period. Another agent can submit work while earlier work is processing,
  allowing PIDE to schedule work according to its dependencies.
- ic2's I/R supports proof-state forks and multiple ML connections, with
  claims on individual REPLs. The check slot therefore does not imply that
  every proof experiment must be sequential. Its concurrency still needs
  an audit: the current Sledgehammer wrapper uses shared state and result
  variables across REPLs.

The paper compares PIDE MCP with upstream I/Q attached to jEdit, standalone
REPLs, and batch builds. Our combination of headless PIDE and I/R does not
fit those categories directly; the paper supplies no benchmark against ic2.

## Shared session arrangement

The strongest initial case is separate agent-owned theories importing a
stable common base in one checkout:

```text
             One resident PIDE session
                  Shared_Base.thy
                  /             \
          Agent_A.thy         Agent_B.thy
            agent A            agent B
```

PIDE MCP's usual transport is stdin/stdout. If each agent process launches
its own configured server command, the agents get separate servers and
sessions. Sharing requires an agent host that exposes one MCP connection
to its workers, or a broker that routes multiple clients to one server,
including request IDs, progress, and cancellation.

A session lock protects individual operations, not an agent's whole
read, reason, and edit sequence. Keep explicit ownership of theories and
coordinate changes to shared imports. Concurrent edits to the same proof
can conflict, and changes to common definitions can invalidate another
agent's work. Text matching in the edit tool provides no per-agent branch
or transaction isolation.

## Proposed pilot

1. Run one PIDE MCP server with one session and two agents. Give each agent
   a separate theory importing the same stable base, in a dedicated agent
   checkout without a human's jEdit editing the files.
2. Verify that the host or broker really routes both agents to that same
   session. Submit work from one agent while the other's proof is still
   processing, and observe whether independent checking overlaps.
3. Compare with the current ic2 workflow using the same tasks and total CPU
   budget. Record completed proofs, wall time, peak aggregate memory, tool
   calls, and duplicated processing of common dependencies.
4. Exercise conflicting edits, a shared-import change, a looping command,
   and an agent disconnection. Check that one agent cannot silently cancel
   or stop the other's work and that results remain attributable.
5. Validate the final development with `isabelle build -D <formal root>`.

Keep ic2 as the default during the pilot. Its daemon-enforced command
deadlines, prover-death reporting, worktree guards, and memory limits are
useful for unattended work. PIDE MCP integration would need corresponding
operational controls. Its standard stdio server stops its sessions when
input closes, so shared ownership of the server lifecycle also matters.

## Sources

The local comparison uses AutoCorrode revision
`dbd474f952aefbded015226d30cec03fbd2afceb`. Upstream source links refer to
the `Isabelle2025-2` branch inspected for the discussion and may change.

- [Original paper](https://zenodo.org/records/21519365) and
  [September revision](https://zenodo.org/records/22726567).
- [PIDE MCP server dispatch](https://github.com/kappelmann/isabelle-pide-mcp/blob/Isabelle2025-2/src/pide_mcp_server.scala),
  [session model and lock](https://github.com/kappelmann/isabelle-pide-mcp/blob/Isabelle2025-2/src/pide_mcp_session.scala),
  [edit tool](https://github.com/kappelmann/isabelle-pide-mcp/blob/Isabelle2025-2/src/Tools/tool_edit.scala),
  and [server lifecycle](https://github.com/kappelmann/isabelle-pide-mcp/blob/Isabelle2025-2/src/pide_mcp.scala).
- [ic2 check slot and MCP tools](../AutoCorrode/ic2/src/iq.scala),
  [incremental check engine](../AutoCorrode/ic2/src/check_engine.scala),
  [I/R connection pool](../AutoCorrode/ir/repl_srv.py), and
  [I/R claims and Sledgehammer wrapper](../AutoCorrode/ir/ir.ML).
- [Current checkout and server architecture](architecture.md).

#!/usr/bin/env python3
"""Generate updated n8n workflow JSON exports from edit suggestions.

Supports two update modes:
1. Freeform natural-language instructions via an OpenAI-compatible API.
2. Deterministic edit specs for common workflow changes.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


class WorkflowValidationError(ValueError):
    """Raised when a workflow JSON export is not valid enough to edit safely."""


class EditSpecError(ValueError):
    """Raised when a deterministic edit spec is malformed."""


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        handle.write(text.rstrip())
        handle.write("\n")


def validate_workflow(workflow: Any) -> dict[str, Any]:
    if not isinstance(workflow, dict):
        raise WorkflowValidationError("Workflow JSON must be an object.")

    if not isinstance(workflow.get("name"), str) or not workflow["name"].strip():
        raise WorkflowValidationError('Workflow must contain a non-empty string "name".')

    nodes = workflow.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise WorkflowValidationError('Workflow must contain a non-empty "nodes" array.')

    connections = workflow.get("connections")
    if not isinstance(connections, dict):
        raise WorkflowValidationError('Workflow must contain a "connections" object.')

    seen_names: set[str] = set()
    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise WorkflowValidationError(f"Node at index {index} must be an object.")

        node_name = node.get("name")
        if not isinstance(node_name, str) or not node_name.strip():
            raise WorkflowValidationError(f"Node at index {index} must contain a non-empty name.")

        if node_name in seen_names:
            raise WorkflowValidationError(
                f'Duplicate node name "{node_name}" detected. Deterministic edits require unique names.'
            )
        seen_names.add(node_name)

        if not isinstance(node.get("type"), str) or not node["type"].strip():
            raise WorkflowValidationError(f'Node "{node_name}" is missing a valid "type".')

    node_names = {node["name"] for node in nodes}
    for source_name, outputs in connections.items():
        if source_name not in node_names:
            raise WorkflowValidationError(
                f'Connection source "{source_name}" does not match any node name.'
            )
        if not isinstance(outputs, dict):
            raise WorkflowValidationError(
                f'Connections for "{source_name}" must be grouped by output type.'
            )

        for output_type, output_groups in outputs.items():
            if not isinstance(output_groups, list):
                raise WorkflowValidationError(
                    f'Connections for "{source_name}.{output_type}" must be an array.'
                )

            for group in output_groups:
                if not isinstance(group, list):
                    raise WorkflowValidationError(
                        f'Connections for "{source_name}.{output_type}" must contain arrays of targets.'
                    )

                for target in group:
                    if not isinstance(target, dict):
                        raise WorkflowValidationError(
                            f'Connection target in "{source_name}.{output_type}" must be an object.'
                        )
                    target_name = target.get("node")
                    if target_name not in node_names:
                        raise WorkflowValidationError(
                            f'Connection from "{source_name}" points to unknown node "{target_name}".'
                        )

    return workflow


def workflow_node_map(workflow: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {node["name"]: node for node in workflow["nodes"]}


def find_node(workflow: dict[str, Any], node_name: str) -> dict[str, Any]:
    try:
        return workflow_node_map(workflow)[node_name]
    except KeyError as exc:
        raise EditSpecError(f'Node "{node_name}" was not found in the workflow.') from exc


PATH_TOKEN_RE = re.compile(r"([^\.\[\]]+)|\[(\d+)\]")


def parse_path(path: str) -> list[str | int]:
    if not isinstance(path, str) or not path.strip():
        raise EditSpecError("Paths must be non-empty strings.")

    tokens: list[str | int] = []
    for part in path.split("."):
        if not part:
            raise EditSpecError(f'Invalid path "{path}". Empty path segment found.')
        matches = list(PATH_TOKEN_RE.finditer(part))
        if not matches or "".join(match.group(0) for match in matches) != part:
            raise EditSpecError(f'Invalid path segment "{part}" in path "{path}".')
        for match in matches:
            if match.group(1) is not None:
                tokens.append(match.group(1))
            else:
                tokens.append(int(match.group(2)))
    return tokens


def _new_container(next_token: str | int | None) -> dict[str, Any] | list[Any]:
    return [] if isinstance(next_token, int) else {}


def _ensure_list_index(values: list[Any], index: int, next_token: str | int | None) -> None:
    while len(values) <= index:
        values.append(None)
    if values[index] is None:
        values[index] = _new_container(next_token)


def get_path_value(payload: Any, path: str) -> Any:
    current = payload
    for token in parse_path(path):
        if isinstance(token, int):
            if not isinstance(current, list) or token >= len(current):
                raise EditSpecError(f'Path "{path}" does not exist.')
            current = current[token]
        else:
            if not isinstance(current, dict) or token not in current:
                raise EditSpecError(f'Path "{path}" does not exist.')
            current = current[token]
    return current


def set_path_value(payload: Any, path: str, value: Any) -> None:
    tokens = parse_path(path)
    current = payload

    for index, token in enumerate(tokens[:-1]):
        next_token = tokens[index + 1]

        if isinstance(token, int):
            if not isinstance(current, list):
                raise EditSpecError(f'Path "{path}" expects a list at token {token}.')
            _ensure_list_index(current, token, next_token)
            current = current[token]
            continue

        if not isinstance(current, dict):
            raise EditSpecError(f'Path "{path}" expects an object at token "{token}".')
        if token not in current or current[token] is None:
            current[token] = _new_container(next_token)
        current = current[token]

    final_token = tokens[-1]
    if isinstance(final_token, int):
        if not isinstance(current, list):
            raise EditSpecError(f'Path "{path}" expects a list before final token {final_token}.')
        while len(current) <= final_token:
            current.append(None)
        current[final_token] = value
    else:
        if not isinstance(current, dict):
            raise EditSpecError(f'Path "{path}" expects an object before final token "{final_token}".')
        current[final_token] = value


def remove_path_value(payload: Any, path: str) -> None:
    tokens = parse_path(path)
    current = payload
    for token in tokens[:-1]:
        if isinstance(token, int):
            if not isinstance(current, list) or token >= len(current):
                raise EditSpecError(f'Path "{path}" does not exist.')
            current = current[token]
        else:
            if not isinstance(current, dict) or token not in current:
                raise EditSpecError(f'Path "{path}" does not exist.')
            current = current[token]

    final_token = tokens[-1]
    if isinstance(final_token, int):
        if not isinstance(current, list) or final_token >= len(current):
            raise EditSpecError(f'Path "{path}" does not exist.')
        current.pop(final_token)
    else:
        if not isinstance(current, dict) or final_token not in current:
            raise EditSpecError(f'Path "{path}" does not exist.')
        del current[final_token]


def add_connection(
    workflow: dict[str, Any],
    *,
    from_node: str,
    to_node: str,
    output_type: str = "main",
    output_index: int = 0,
    input_type: str = "main",
    input_index: int = 0,
) -> None:
    find_node(workflow, from_node)
    find_node(workflow, to_node)

    connections = workflow.setdefault("connections", {})
    outputs = connections.setdefault(from_node, {})
    output_groups = outputs.setdefault(output_type, [])
    while len(output_groups) <= output_index:
        output_groups.append([])

    entry = {"node": to_node, "type": input_type, "index": input_index}
    if entry not in output_groups[output_index]:
        output_groups[output_index].append(entry)


def remove_connection(
    workflow: dict[str, Any],
    *,
    from_node: str,
    to_node: str,
    output_type: str = "main",
    output_index: int = 0,
    input_type: str = "main",
    input_index: int = 0,
) -> None:
    connections = workflow.get("connections", {})
    outputs = connections.get(from_node, {})
    output_groups = outputs.get(output_type, [])
    if output_index >= len(output_groups):
        return

    expected = {"node": to_node, "type": input_type, "index": input_index}
    output_groups[output_index] = [
        target for target in output_groups[output_index] if target != expected
    ]


def apply_operation(workflow: dict[str, Any], operation: dict[str, Any]) -> None:
    op = operation.get("op")
    if not isinstance(op, str) or not op:
        raise EditSpecError('Each operation must contain a non-empty string "op".')

    if op == "renameWorkflow":
        value = operation.get("value")
        if not isinstance(value, str) or not value.strip():
            raise EditSpecError('renameWorkflow requires a non-empty string "value".')
        workflow["name"] = value
        return

    if op == "setWorkflowValue":
        set_path_value(workflow, operation["path"], operation.get("value"))
        return

    if op == "removeWorkflowValue":
        remove_path_value(workflow, operation["path"])
        return

    if op == "setNodeValue":
        node = find_node(workflow, operation["nodeName"])
        set_path_value(node, operation["path"], operation.get("value"))
        return

    if op == "removeNodeValue":
        node = find_node(workflow, operation["nodeName"])
        remove_path_value(node, operation["path"])
        return

    if op == "updateNodeParameters":
        node = find_node(workflow, operation["nodeName"])
        changes = operation.get("changes")
        if not isinstance(changes, dict) or not changes:
            raise EditSpecError('updateNodeParameters requires a non-empty "changes" object.')
        for relative_path, value in changes.items():
            target_path = "parameters" if relative_path == "" else f"parameters.{relative_path}"
            set_path_value(node, target_path, value)
        return

    if op == "replaceInNodeString":
        node = find_node(workflow, operation["nodeName"])
        field_path = operation.get("path") or operation.get("fieldPath")
        if not isinstance(field_path, str) or not field_path.strip():
            raise EditSpecError('replaceInNodeString requires "path" or "fieldPath".')

        original = get_path_value(node, field_path)
        if not isinstance(original, str):
            raise EditSpecError(
                f'Path "{field_path}" on node "{operation["nodeName"]}" is not a string.'
            )

        search = operation.get("search")
        replace = operation.get("replace", "")
        if not isinstance(search, str) or search == "":
            raise EditSpecError('replaceInNodeString requires a non-empty "search" string.')
        if not isinstance(replace, str):
            raise EditSpecError('replaceInNodeString requires a string "replace" value.')

        count = operation.get("count")
        if count is None:
            updated = original.replace(search, replace)
        else:
            if not isinstance(count, int) or count < 0:
                raise EditSpecError('replaceInNodeString "count" must be a non-negative integer.')
            updated = original.replace(search, replace, count)

        if updated == original:
            raise EditSpecError(
                f'Could not find "{search}" in "{field_path}" for node "{operation["nodeName"]}".'
            )

        set_path_value(node, field_path, updated)
        return

    if op == "addConnection":
        add_connection(
            workflow,
            from_node=operation["fromNode"],
            to_node=operation["toNode"],
            output_type=operation.get("outputType", "main"),
            output_index=operation.get("outputIndex", 0),
            input_type=operation.get("inputType", "main"),
            input_index=operation.get("inputIndex", 0),
        )
        return

    if op == "removeConnection":
        remove_connection(
            workflow,
            from_node=operation["fromNode"],
            to_node=operation["toNode"],
            output_type=operation.get("outputType", "main"),
            output_index=operation.get("outputIndex", 0),
            input_type=operation.get("inputType", "main"),
            input_index=operation.get("inputIndex", 0),
        )
        return

    raise EditSpecError(f'Unsupported operation "{op}".')


def load_edit_spec(path: Path) -> dict[str, Any]:
    payload = load_json(path)
    if isinstance(payload, list):
        payload = {"operations": payload}

    if not isinstance(payload, dict):
        raise EditSpecError("Edit spec must be either an object or an array of operations.")

    operations = payload.get("operations")
    if not isinstance(operations, list) or not operations:
        raise EditSpecError('Edit spec must contain a non-empty "operations" array.')

    for index, operation in enumerate(operations):
        if not isinstance(operation, dict):
            raise EditSpecError(f"Operation at index {index} must be an object.")

    return payload


def apply_edit_spec(workflow: dict[str, Any], edit_spec: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    updated = copy.deepcopy(workflow)
    for operation in edit_spec["operations"]:
        apply_operation(updated, operation)

    validate_workflow(updated)
    summary = edit_spec.get("summary")
    summary_lines = [summary] if isinstance(summary, str) and summary.strip() else []
    return updated, summary_lines


def strip_code_fences(text: str) -> str:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```[a-zA-Z0-9_-]*\n", "", cleaned)
        cleaned = re.sub(r"\n```$", "", cleaned)
    return cleaned.strip()


def build_llm_prompt(workflow: dict[str, Any], instructions: str) -> str:
    workflow_json = json.dumps(workflow, indent=2)
    return (
        "Update the exported n8n workflow JSON below.\n\n"
        "Requirements:\n"
        '1. Return a single JSON object with exactly two top-level keys: "workflow" and "summary".\n'
        '2. "workflow" must be a complete, valid n8n workflow export.\n'
        '3. "summary" must be an array of short strings describing the changes you made.\n'
        "4. Preserve existing node IDs, credentials, types, and connection structure unless the instructions require a change.\n"
        "5. Make the smallest changes that satisfy the instructions.\n"
        "6. Keep the JSON importable in n8n.\n"
        "7. Do not wrap the response in markdown fences.\n\n"
        f"User instructions:\n{instructions.strip()}\n\n"
        f"Current workflow JSON:\n{workflow_json}\n"
    )


def _extract_text_content(message: dict[str, Any]) -> str:
    content = message.get("content")
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: list[str] = []
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") in {"text", "output_text"} and isinstance(block.get("text"), str):
                parts.append(block["text"])
        return "\n".join(parts)

    raise WorkflowValidationError("LLM response did not contain a text message.")


def request_llm_update(
    workflow: dict[str, Any], instructions: str, model: str, timeout_seconds: int
) -> tuple[dict[str, Any], list[str]]:
    api_key = os.getenv("OPENAI_API_KEY") or os.getenv("N8N_WORKFLOW_OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "No API key found. Set OPENAI_API_KEY (or N8N_WORKFLOW_OPENAI_API_KEY), "
            "or use --edit-spec for deterministic updates."
        )

    base_url = os.getenv("OPENAI_BASE_URL") or os.getenv("N8N_WORKFLOW_OPENAI_BASE_URL")
    if not base_url:
        base_url = "https://api.openai.com/v1"
    base_url = base_url.rstrip("/")

    prompt = build_llm_prompt(workflow, instructions)
    payload = {
        "model": model,
        "temperature": 0.1,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are an expert n8n workflow editor. "
                    "Return valid JSON only and preserve existing workflow structure unless changes are requested."
                ),
            },
            {
                "role": "user",
                "content": prompt,
            },
        ],
    }

    request = urllib.request.Request(
        url=f"{base_url}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw_response = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"LLM request failed with HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"LLM request failed: {exc.reason}") from exc

    decoded = json.loads(raw_response)
    choices = decoded.get("choices")
    if not isinstance(choices, list) or not choices:
        raise RuntimeError("LLM response did not include any choices.")

    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise RuntimeError("LLM response did not include a valid message.")

    content = strip_code_fences(_extract_text_content(message))
    parsed = json.loads(content)
    if not isinstance(parsed, dict):
        raise RuntimeError("LLM response must be a JSON object.")

    updated_workflow = parsed.get("workflow")
    summary = parsed.get("summary", [])
    if not isinstance(summary, list):
        raise RuntimeError('LLM response "summary" must be an array of strings.')

    validate_workflow(updated_workflow)
    return updated_workflow, [str(item) for item in summary]


def summarize_changes(before: dict[str, Any], after: dict[str, Any]) -> list[str]:
    summary: list[str] = []

    if before.get("name") != after.get("name"):
        summary.append(f'Renamed workflow from "{before.get("name")}" to "{after.get("name")}".')

    before_nodes = workflow_node_map(before)
    after_nodes = workflow_node_map(after)

    before_names = set(before_nodes)
    after_names = set(after_nodes)

    added = sorted(after_names - before_names)
    removed = sorted(before_names - after_names)

    for node_name in added[:10]:
        summary.append(f'Added node "{node_name}".')
    if len(added) > 10:
        summary.append(f"Added {len(added) - 10} more nodes.")

    for node_name in removed[:10]:
        summary.append(f'Removed node "{node_name}".')
    if len(removed) > 10:
        summary.append(f"Removed {len(removed) - 10} more nodes.")

    changed_nodes: list[str] = []
    for node_name in sorted(before_names & after_names):
        before_blob = json.dumps(before_nodes[node_name], sort_keys=True)
        after_blob = json.dumps(after_nodes[node_name], sort_keys=True)
        if before_blob != after_blob:
            changed_nodes.append(node_name)

    for node_name in changed_nodes[:20]:
        summary.append(f'Updated node "{node_name}".')
    if len(changed_nodes) > 20:
        summary.append(f"Updated {len(changed_nodes) - 20} more nodes.")

    if json.dumps(before.get("connections", {}), sort_keys=True) != json.dumps(
        after.get("connections", {}), sort_keys=True
    ):
        summary.append("Updated workflow connections.")

    if not summary:
        summary.append("No structural differences detected between the input and output workflow.")

    return summary


def build_output_paths(
    input_path: Path, output_path: str | None, output_dir: str | None
) -> tuple[Path, Path]:
    if output_path:
        workflow_path = Path(output_path)
    else:
        timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
        directory = Path(output_dir or "generated-workflows")
        workflow_path = directory / f"{input_path.stem}__updated__{timestamp}.json"

    changes_path = workflow_path.with_suffix(".changes.md")
    return workflow_path, changes_path


def render_summary(title: str, summary_lines: list[str]) -> str:
    lines = [f"# {title}", ""]
    for item in summary_lines:
        lines.append(f"- {item}")
    return "\n".join(lines).rstrip() + "\n"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create an updated n8n workflow export from freeform suggestions "
            "or a deterministic edit spec."
        )
    )
    parser.add_argument("--input", required=True, help="Path to the base n8n workflow JSON file.")
    parser.add_argument("--instructions", help="Freeform natural-language workflow changes.")
    parser.add_argument(
        "--instructions-file",
        help="Path to a text file that contains freeform change instructions.",
    )
    parser.add_argument(
        "--edit-spec",
        help="Path to a deterministic JSON edit spec for common workflow updates.",
    )
    parser.add_argument(
        "--output",
        help="Optional explicit path for the updated workflow JSON file.",
    )
    parser.add_argument(
        "--output-dir",
        help="Directory for generated workflow files when --output is not set.",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("N8N_WORKFLOW_MODEL", "gpt-4.1-mini"),
        help="OpenAI-compatible model name for freeform suggestion mode.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=120,
        help="HTTP timeout for LLM requests in seconds.",
    )
    return parser.parse_args(argv)


def read_instructions(args: argparse.Namespace) -> str | None:
    if args.instructions and args.instructions_file:
        raise SystemExit("Use either --instructions or --instructions-file, not both.")

    if args.instructions:
        return args.instructions.strip()

    if args.instructions_file:
        return Path(args.instructions_file).read_text(encoding="utf-8").strip()

    return None


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    instructions = read_instructions(args)
    if bool(instructions) == bool(args.edit_spec):
        raise SystemExit(
            "Choose exactly one update mode: provide freeform instructions or provide --edit-spec."
        )

    input_path = Path(args.input)
    workflow = validate_workflow(load_json(input_path))

    if args.edit_spec:
        updated_workflow, supplied_summary = apply_edit_spec(
            workflow, load_edit_spec(Path(args.edit_spec))
        )
    else:
        updated_workflow, supplied_summary = request_llm_update(
            workflow,
            instructions=instructions or "",
            model=args.model,
            timeout_seconds=args.timeout_seconds,
        )

    validate_workflow(updated_workflow)

    output_path, changes_path = build_output_paths(input_path, args.output, args.output_dir)
    change_summary = supplied_summary or summarize_changes(workflow, updated_workflow)

    save_json(output_path, updated_workflow)
    save_text(
        changes_path,
        render_summary("Workflow update summary", change_summary),
    )

    print(f"Updated workflow written to: {output_path}")
    print(f"Change summary written to:   {changes_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (WorkflowValidationError, EditSpecError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)

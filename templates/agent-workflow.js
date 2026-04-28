#!/usr/bin/env node
"use strict";

const fs = require("node:fs");

const workflow = JSON.parse(fs.readFileSync("agent.workflow.json", "utf8"));
const command = process.argv[2] || "instructions";

function validate() {
	const failures = [];
	if (!workflow.baseBranch) failures.push("baseBranch is required");
	if (!workflow.syncCommand) failures.push("syncCommand is required");
	if (!workflow.pr?.createCommand) failures.push("pr.createCommand is required");
	if (!workflow.pr?.stopBeforeMerge) failures.push("pr.stopBeforeMerge must be true");
	if (!workflow.checks?.default) failures.push("checks.default is required");
	if (failures.length > 0) {
		console.error(failures.map((failure) => `- ${failure}`).join("\n"));
		process.exit(1);
	}
	console.log("Agent workflow validation passed.");
}

function instructions() {
	validate();
	console.log(`Sync before work: ${workflow.syncCommand}`);
	console.log(`Run default checks: ${workflow.checks.default}`);
	console.log(`Create PR: ${workflow.pr.createCommand}`);
	if (workflow.review?.watchCiCommand) console.log(`Watch CI: ${workflow.review.watchCiCommand}`);
	if (workflow.review?.readCommentsCommand) console.log(`Read comments: ${workflow.review.readCommentsCommand}`);
	console.log("Stop before merge.");
}

if (command === "validate") {
	validate();
} else if (command === "instructions") {
	instructions();
} else {
	console.error("Usage: node scripts/agent-workflow.js <validate|instructions>");
	process.exit(1);
}

#!/usr/bin/env node

/**
 * CAWS Validation Criteria Enforcement
 *
 * This script enforces validation requirements as a key part of acceptance criteria,
 * ensuring all features have empirical evidence before acceptance.
 *
 * Usage: node validate_acceptance_criteria.js --pr-path <path> --schema-path <schema>
 */

const fs = require("fs");
const path = require("path");
const { JSONSchema7 } = require("json-schema");

class ValidationEnforcer {
  constructor(schemaPath, prPath) {
    this.schemaPath = schemaPath;
    this.prPath = prPath;
    this.schema = null;
    this.prData = null;
    this.violations = [];
    this.warnings = [];
  }

  async initialize() {
    try {
      // Load validation schema
      const schemaContent = fs.readFileSync(this.schemaPath, "utf8");
      this.schema = JSON.parse(schemaContent);

      // Load PR data
      const prContent = fs.readFileSync(this.prPath, "utf8");
      this.prData = JSON.parse(prContent);

      console.log("✅ Validation enforcer initialized");
    } catch (error) {
      console.error(
        "❌ Failed to initialize validation enforcer:",
        error.message
      );
      process.exit(1);
    }
  }

  validateAcceptanceCriteria() {
    console.log("\n🔍 Validating Acceptance Criteria...\n");

    // Check if validation is required
    if (!this.prData.validation_trust_score) {
      this.violations.push(
        "Missing validation_trust_score - validation evidence required"
      );
      return false;
    }

    // Check minimum trust score
    if (this.prData.validation_trust_score.overall < 0.85) {
      this.violations.push(
        `Validation trust score ${this.prData.validation_trust_score.overall} below minimum 0.85`
      );
    }

    // Validate empirical evidence
    if (!this.prData.empirical_evidence?.required) {
      this.violations.push("Empirical evidence requirement not satisfied");
    }

    // Validate test completeness
    const testCompleteness = this.prData.test_completeness;
    if (testCompleteness) {
      if (testCompleteness.unit_coverage < 0.8) {
        this.warnings.push(
          `Unit test coverage ${testCompleteness.unit_coverage} below target 0.8`
        );
      }
      if (testCompleteness.safety_coverage < 0.9) {
        this.violations.push(
          `Safety test coverage ${testCompleteness.safety_coverage} below required 0.9`
        );
      }
    }

    // Validate safety validation
    const safety = this.prData.safety_validation;
    if (safety) {
      if (!safety.atomic_operations?.validated) {
        this.violations.push("Atomic operations not validated");
      }
      if (safety.error_recovery?.recovery_rate < 0.95) {
        this.warnings.push(
          `Error recovery rate ${safety.error_recovery.recovery_rate} below target 0.95`
        );
      }
    }

    // Validate performance validation
    const perf = this.prData.performance_validation;
    if (perf) {
      if (
        !perf.large_dataset_testing?.datasets_tested ||
        perf.large_dataset_testing.datasets_tested < 3
      ) {
        this.violations.push("Large dataset testing insufficient");
      }
      if (perf.claims_validation?.accuracy_score < 0.8) {
        this.violations.push(
          "Performance claims accuracy below acceptable level"
        );
      }
    }

    // Check for validation gaps
    if (this.prData.validation_gaps?.length > 0) {
      this.warnings.push(
        `Validation gaps identified: ${this.prData.validation_gaps.join(", ")}`
      );
    }

    return this.violations.length === 0;
  }

  validateEvidenceQuality() {
    console.log("🔍 Validating Evidence Quality...\n");

    const empirical = this.prData.empirical_evidence;
    if (!empirical) {
      this.violations.push("No empirical evidence provided");
      return false;
    }

    // Validate benchmarks
    for (const benchmark of empirical.benchmarks || []) {
      if (!benchmark.evidence) {
        this.violations.push(`Benchmark ${benchmark.name} missing evidence`);
        continue;
      }

      const evidence = benchmark.evidence;
      if (evidence.p_value > 0.05) {
        this.violations.push(
          `Benchmark ${benchmark.name} not statistically significant (p=${evidence.p_value})`
        );
      }

      if (evidence.sample_size < 1000) {
        this.warnings.push(
          `Benchmark ${benchmark.name} sample size ${evidence.sample_size} < recommended 1000`
        );
      }
    }

    // Validate evidence quality standards
    const quality = empirical.evidence_quality;
    if (quality) {
      if (quality.statistical_significance > 0.05) {
        this.violations.push("Statistical significance not met");
      }
      if (quality.sample_adequacy < 0.8) {
        this.warnings.push("Sample adequacy below acceptable level");
      }
      if (quality.measurement_accuracy < 0.9) {
        this.warnings.push("Measurement accuracy below acceptable level");
      }
    }

    return this.violations.length === 0;
  }

  validateRequiredArtifacts() {
    console.log("🔍 Validating Required Artifacts...\n");

    const artifacts = this.prData.evidence_artifacts;
    if (!artifacts) {
      this.violations.push("No evidence artifacts provided");
      return false;
    }

    const requiredArtifacts = [
      "performance_benchmarks",
      "safety_test_results",
      "statistical_analysis",
    ];

    for (const artifactType of requiredArtifacts) {
      if (!artifacts[artifactType]) {
        this.violations.push(`Missing required artifact: ${artifactType}`);
        continue;
      }

      const artifact = artifacts[artifactType];
      if (!artifact.file) {
        this.violations.push(`Artifact ${artifactType} missing file reference`);
      } else {
        // Check if file exists
        const artifactPath = path.join(
          path.dirname(this.prPath),
          artifact.file
        );
        if (!fs.existsSync(artifactPath)) {
          this.violations.push(`Artifact file not found: ${artifactPath}`);
        }
      }
    }

    return this.violations.length === 0;
  }

  generateValidationReport() {
    console.log("\n📊 VALIDATION REPORT\n");

    if (this.violations.length === 0) {
      console.log("✅ All validation requirements satisfied");
      console.log(
        `✅ Overall trust score: ${this.prData.validation_trust_score.overall}`
      );

      if (this.warnings.length > 0) {
        console.log("\n⚠️  Warnings:");
        this.warnings.forEach((warning) => console.log(`  - ${warning}`));
      }

      return {
        valid: true,
        trustScore: this.prData.validation_trust_score.overall,
        warnings: this.warnings,
        violations: [],
      };
    } else {
      console.log("❌ Validation failed with the following violations:");
      this.violations.forEach((violation) => console.log(`  ❌ ${violation}`));

      return {
        valid: false,
        trustScore: this.prData.validation_trust_score?.overall || 0,
        warnings: this.warnings,
        violations: this.violations,
      };
    }
  }

  async runValidation() {
    await this.initialize();

    const acceptanceValid = this.validateAcceptanceCriteria();
    const evidenceValid = this.validateEvidenceQuality();
    const artifactsValid = this.validateRequiredArtifacts();

    const report = this.generateValidationReport();

    // Exit with appropriate code for CI/CD
    if (report.valid) {
      console.log("\n🎉 Validation passed - ready for acceptance");
      process.exit(0);
    } else {
      console.log("\n❌ Validation failed - requires fixes before acceptance");
      process.exit(1);
    }
  }
}

// CLI interface
function parseArgs() {
  const args = {};
  process.argv.slice(2).forEach((arg) => {
    if (arg.startsWith("--")) {
      const [key, value] = arg.substring(2).split("=");
      args[key] = value || true;
    }
  });
  return args;
}

async function main() {
  const args = parseArgs();

  if (!args["pr-path"]) {
    console.error(
      "Usage: node validate_acceptance_criteria.js --pr-path <path> --schema-path <schema>"
    );
    process.exit(1);
  }

  const enforcer = new ValidationEnforcer(args["schema-path"], args["pr-path"]);
  await enforcer.runValidation();
}

// Run if called directly
if (require.main === module) {
  main().catch((error) => {
    console.error("❌ Validation failed with error:", error.message);
    process.exit(1);
  });
}

module.exports = { ValidationEnforcer };

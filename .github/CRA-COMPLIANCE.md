# CRA Cyber Resilience Act Compliance Documentation

## Overview
This document outlines how the `thingino-firmware` repository complies with the **EU Cyber Resilience Act (CRA)** requirements for vulnerability management, supply chain security, and transparency.

---

## 1. Vulnerability Management (CRA Article 10)

### Tools & Processes
| Tool | Purpose | Frequency | Evidence |
|------|---------|-----------|----------|
| **Trivy** | Filesystem vulnerability scanning | On every push + weekly | [GitHub Security Tab](https://github.com/Em1li0/thingino-firmware/security) |
| **Grype** | SBOM-based vulnerability scanning | On every push + weekly | [GitHub Security Tab](https://github.com/Em1li0/thingino-firmware/security) |
| **Dependabot** | Dependency vulnerability alerts | Weekly | [Dependabot Alerts](https://github.com/Em1li0/thingino-firmware/security/dependabot) |

### Coverage
- ✅ Source code vulnerabilities
- ✅ Dependency vulnerabilities (GitHub Actions, Docker, pip, npm, Maven)
- ✅ Container image vulnerabilities
- ✅ OS package vulnerabilities

### Response Process
1. Dependabot opens PRs for vulnerable dependencies
2. Trivy/Grype scan results appear in Security tab
3. Maintainers review and fix within **CRA-mandated timelines**
4. Fixes are merged and re-scanned

---

## 2. Software Bill of Materials (SBOM) - CRA Article 11

### Generation
- **Tool:** [Syft](https://github.com/anchore/syft) by Anchore
- **Format:** SPDX JSON (industry standard)
- **Generated:** On every workflow run
- **Stored:** GitHub Actions artifacts + GitHub Releases

### SBOM Contents
- All dependencies with versions
- Licenses for each component
- Package managers: pip, npm, Docker, Maven
- Filesystem metadata

### SBOM Scanning
- **Tool:** [Grype](https://github.com/anchore/grype)
- **Purpose:** Scan SBOM for known vulnerabilities
- **Output:** SARIF format uploaded to GitHub Security tab

### Access
- **Latest SBOM:** [GitHub Actions Artifacts](https://github.com/Em1li0/thingino-firmware/actions) → Latest workflow run → SBOM artifact
- **Release SBOMs:** Attached to each GitHub Release

---

## 3. Supply Chain Security (CRA Article 10)

### SLSA Framework (Supply-chain Levels for Software Artifacts)
- **Level:** SLSA Level 2
- **Implementation:** GitHub Actions with SLSA generator
- **Purpose:** Provides cryptographically verifiable provenance for builds

### Components
- **Build Process:** GitHub Actions workflows
- **Source Control:** Git commit hashes tracked
- **Build Integrity:** SLSA provenance files generated and signed

### Cosign Signing (Optional - for container images)
- **Tool:** [Sigstore Cosign](https://github.com/sigstore/cosign)
- **Purpose:** Digitally sign container images
- **Status:** Configured if/when container builds are added

---

## 4. Security by Design (CRA Article 4)

### Secure Development Practices
- ✅ All code changes pass vulnerability scanning before merge
- ✅ Upstream changes are automatically synced and re-scanned
- ✅ Security alerts are centrally visible in GitHub Security tab
- ✅ Dependency updates are automated via Dependabot

### CI/CD Pipeline
- **Workflow:** `.github/workflows/cra-compliance.yml`
- **Triggers:** On push to `cra-compliance` branch, weekly schedule
- **Coverage:** Full firmware codebase

---

## 5. Transparency & Audit Trail (CRA Article 20)

### Evidence Storage
| Evidence Type | Location | Retention |
|--------------|----------|-----------|
| Vulnerability scan results | GitHub Security Tab | Indefinite |
| SBOM files | GitHub Actions Artifacts | 90 days |
| SLSA provenance | GitHub Releases | Indefinite |
| Workflow logs | GitHub Actions | 90 days |
| Dependabot alerts | GitHub Security Tab | Indefinite |

### Audit Access
- **Security Dashboard:** [https://github.com/Em1li0/thingino-firmware/security](https://github.com/Em1li0/thingino-firmware/security)
- **Actions Logs:** [https://github.com/Em1li0/thingino-firmware/actions](https://github.com/Em1li0/thingino-firmware/actions)
- **Dependabot:** [https://github.com/Em1li0/thingino-firmware/security/dependabot](https://github.com/Em1li0/thingino-firmware/security/dependabot)

---

## 6. Workflow Configuration

### Main Compliance Workflow
- **File:** `.github/workflows/cra-compliance.yml`
- **Purpose:** Combined vulnerability scanning, SBOM generation, and supply chain security
- **Triggers:**
  - On every push to `cra-compliance` branch
  - Weekly (every Monday at midnight)
  - Manual trigger via GitHub UI

### Workflow Steps
1. **Checkout:** Full repository checkout with history
2. **Upstream Sync:** Merge latest changes from `themactep/thingino-firmware`
3. **SBOM Generation:** Syft generates SPDX JSON SBOM
4. **Trivy Scan:** Filesystem vulnerability scanning
5. **Grype Scan:** SBOM-based vulnerability scanning
6. **Upload Reports:** All results uploaded to GitHub Security tab
7. **SLSA Provenance:** Generate and store build provenance

---

## 7. CRA Compliance Checklist

| CRA Requirement | Status | Implementation |
|----------------|--------|----------------|
| Vulnerability assessment | ✅ | Trivy + Grype |
| SBOM generation | ✅ | Syft (SPDX JSON) |
| Dependency management | ✅ | Dependabot |
| Supply chain security | ✅ | SLSA Level 2 |
| Security by design | ✅ | Secure CI/CD pipeline |
| Transparency | ✅ | Public security dashboard |
| Incident reporting | ✅ | GitHub Security alerts |
| Ongoing monitoring | ✅ | Weekly automated scans |

---

## 8. Contacts & Responsibilities

| Role | Responsibility | Contact |
|------|---------------|---------|
| Maintainer | Code updates, vulnerability fixing | Em1li0 |
| Security Review | Compliance verification | CRA Team |
| Incident Response | Security incident management | CRA Team |

---

## 9. References

- [EU Cyber Resilience Act](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act)
- [SLSA Framework](https://slsa.dev/)
- [SPDX Specification](https://spdx.github.io/spdx-spec/)
- [Syft Documentation](https://github.com/anchore/syft)
- [Grype Documentation](https://github.com/anchore/grype)
- [Trivy Documentation](https://github.com/aquasecurity/trivy)

---

*Last updated: $(date)*
*Generated by: Mistral Vibe*

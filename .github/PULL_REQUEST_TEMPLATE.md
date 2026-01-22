## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an 'x' -->

- [ ] Infrastructure change (VPC, EKS, RDS, etc.)
- [ ] Module update
- [ ] Configuration change
- [ ] Documentation update
- [ ] CI/CD pipeline change
- [ ] Bug fix
- [ ] Other (please describe):

## Environments Affected

<!-- Mark all that apply -->

- [ ] Development
- [ ] Staging
- [ ] Production
- [ ] DR (Disaster Recovery)

## Changes Made

<!-- List the specific changes made in this PR -->

- 
- 
- 

## Terraform Plan Summary

<!-- The workflow will automatically post the plan, but you can add key highlights here -->

**Resources to be added:** 
**Resources to be changed:** 
**Resources to be destroyed:** 

## Cost Impact

<!-- Will be automatically added by Infracost if configured -->

**Estimated monthly cost change:** 
**Justification:** 

## Testing Checklist

<!-- Mark completed items with an 'x' -->

- [ ] `terraform fmt` run successfully
- [ ] `terraform validate` passes
- [ ] Tested in development environment
- [ ] Security scan reviewed (tfsec)
- [ ] No secrets or sensitive data exposed
- [ ] Documentation updated (if needed)
- [ ] Rollback plan identified

## Deployment Plan

### Dev Deployment
<!-- Will happen automatically on merge to develop -->
- [ ] Merge to `develop` branch
- [ ] Monitor deployment logs
- [ ] Verify functionality in dev

### Staging/Prod Deployment
<!-- Will happen automatically on merge to main -->
- [ ] Merge to `main` branch
- [ ] Monitor staging deployment
- [ ] Verify staging functionality
- [ ] Monitor prod deployment
- [ ] Verify prod functionality
- [ ] Monitor DR deployment (if applicable)

## Rollback Plan

<!-- Describe how to rollback these changes if needed -->

**Rollback steps:**
1. 
2. 
3. 

**Estimated rollback time:** 

## Security Considerations

<!-- Mark completed items with an 'x' -->

- [ ] No hardcoded credentials
- [ ] IAM permissions follow least-privilege
- [ ] Security groups properly restricted
- [ ] Encryption enabled where required
- [ ] Secrets stored in AWS Secrets Manager
- [ ] No sensitive data in logs

## Breaking Changes

<!-- List any breaking changes that require coordination -->

- [ ] No breaking changes
- [ ] Breaking changes (describe below):

<!-- If breaking changes, describe them here -->

## Dependencies

<!-- List any dependencies or prerequisites -->

- [ ] No external dependencies
- [ ] Depends on other PRs:
- [ ] Requires manual steps:
- [ ] Requires AWS CLI commands:

## Screenshots/Logs

<!-- Add any relevant screenshots or log outputs -->

## Checklist

<!-- Final verification before merge -->

- [ ] PR title follows conventional commit format
- [ ] Changes have been peer reviewed
- [ ] All GitHub Actions checks passed
- [ ] Plan output reviewed and approved
- [ ] Cost impact acceptable
- [ ] Security scan passed
- [ ] Documentation updated
- [ ] Team notified of deployment schedule

## Additional Notes

<!-- Any additional information reviewers should know -->

---

## Reviewer Guidelines

**For Reviewers:**
1. ✅ Review the Terraform plan output in comments
2. ✅ Check cost impact (Infracost comment)
3. ✅ Verify security scan results
4. ✅ Ensure proper environment targeting
5. ✅ Validate rollback plan exists
6. ✅ Confirm tests completed in dev (for prod changes)

**Approval Criteria:**
- [ ] Code follows Terraform best practices
- [ ] Changes are well documented
- [ ] No security concerns
- [ ] Cost impact acceptable
- [ ] Plan output reviewed and reasonable
- [ ] Testing completed appropriately

---

**Deployment Timeline:**
- **Dev:** Deploys on merge to `develop` (~20-25 min)
- **Staging/Prod:** Deploys on merge to `main` (~60-70 min)
- **DR:** Deploys automatically after prod (~35-40 min)

/cc @platform-team

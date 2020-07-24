## Description
The contents of this repo provide an example of how to insert Azure DSC workflow into a pipeline, end-to-end.

This also uses DSC Composite module, to compartmentalize your DSC code into managable sections.

**Note:** on the initial run, this set of pipelines will likely take over 30 minutes to complete.

**To-Do:**
There is a bit of a chicken-egg scenario with the pipeline triggers. If I update the composite module, I need the module pipeline to run before the DSC import/compile pipeline.
But the module doesn't need to be re-imported every time a change occurs within the repo, so I don't want to collapse it into one pipeline.
Some linked dependency needs to be created here.

## Prerequisites
- An Azure Subscription in which to deploy resources
- An Azure KeyVault that will be used to generate certificates
- An Azure Storage Account with a container, to store composite module zip
- An Azure DevOps organization you can create pipelines in
- An Azure Service Principal with the following RBAC: (so that it can itself create new service principals)
    - must be "Application Administrator" on the Azure AD tenant
    - must be "Owner" on the subscription
    - must have appropriate rights to an access policy on the KeyVault to generate and retrieve Certificates
    - must have API permissions within the Azure Active directory for:
        - API: Azure Active Directory Graph | Type: Application | Permission: Application.ReadWrite.OwnedBy
        - API: Microsoft Graph | Type: Application | Permission: Application.ReadWrite.OwnedBy
- An Azure DevOps Service Connection linked to the Service Principal above

## Deployment
Assuming you're connecting to a GitHub repository containing this code:
- Populate the "dsc_parameters.ps1" file with values as you desire
- Within Azure DevOps, create a new Pipeline, and link it to your GitHub (creating a service connection using OATH login)
- Select an existing yaml file to create the pipeline from
    - Do this twice for "ModuleDeploy-pipeline.yml" and "azure-pipelines.yml"
    - Don't forget to rename your pipelines in DevOps portal, to something meaningful
- Manually run the "ModuleDeploy-pipeline.yml" pipeline

## Results
- ModuleDeploy-pipeline.yml pipeline runs and
    - takes module from repository and creates a zip file
    - uploads DSC composite module zip to blob storage
    - creates automation account if it doesn't exist
    - imports DSC composite module to automation account from blob storage (with SAS)
- azure-pipelines.yml pipeline runs and:
    - creates automation account if it doesn't exist
    - imports/updates Az.Accounts module
    - imports/updates remaining modules identified in parameters
    - creates new automation runas account (and required service principal) if it doesn't exist (generating an Azure KeyVault certificate to do so)
    - performs a 'first-time' run of the "Update-AutomationAzureModulesForAccount" runbook (because automation account is created with out-of-date default modules)
    - imports DSC configuration
    - compiles DSC configuration against configuration data
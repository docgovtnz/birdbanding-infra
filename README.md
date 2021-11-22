# doc-birdbanding-infra

Background: https://docgovtnz.github.io/docs/projects/falcon

Prerequisite infrastructure for FALCON.

Includes:
* Alerting, Documentation, Public-hosted zone, staging resources
* Hosting infrastructure (Single-page application)
* Authentication (Cognito) and Data infrastructure (Postgres database)
* Common code (Lambda layers)

## Notes to users

This code contains AWS-specific infrastructure code that may be useful in spinning up a version of FALCON. Given the nature of cloud-configuration, this repo has been audited and DOC-specific parts removed and replaced with example configurations.

Given the redaction process, it is not expected that this code will deploy out-of-the-box, but it is provided in the hope it can be a useful reference.

Outside of cloud configuration, note there is SQL code provided in `./sql` that helps to set up the database for the backend.

## Structure

* `./cfn/dpy`
  * CloudFormation templates for AWS infrastructure
* `./cfn/pre`
  * Pre-requisite CloudFormation templates
* `./sql`
  * Core SQL scripts (prefixed with numeric order where there are dependencies)

## Licence

FALCON (New Zealand Bird Banding Database)  
Copyright (C) 2021 Department of Conservation | Te Papa Atawhai, Pikselin Limited, Fronde Systems Group Limited

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

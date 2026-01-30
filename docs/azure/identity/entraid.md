# EntraID

Based on the sources provided, **Microsoft Entra ID** is a modern **identity provider** and cloud-based directory service that acts as the backbone for securing access, empowering users, and enabling collaboration in digital environments. It serves as the central hub for managing identities—whether they are users, devices, or applications—and controls how they access resources in the cloud and on-premises.

Here is a comprehensive breakdown of what Microsoft Entra ID is and its key functions:

#### 1. A Modern Identity Provider

At its core, Entra ID functions as an **identity provider (IdP)**. Traditionally, authentication happened between a client and a server (often using username and password). In the modern model used by Entra ID:

* **Authentication & Tokens:** Entra ID validates a user's identity and issues a **security token** (using protocols like SAML, WS-Federation, or OpenID Connect).
* **Single Sign-On (SSO):** Because applications trust Entra ID as the provider, users do not need to log in repeatedly for every service. Entra ID handles the authentication and provides the necessary cryptographic tokens to the application, enabling **Single Sign-On**.
* **Zero Trust Foundation:** Entra ID is critical to the **Zero Trust** security model. It facilitates the principle of "verify explicitly" by authenticating based on data points like user identity, location, and device health before granting access.

#### 2. The Organization Representation (Tenant)

To use Entra ID, an administrator creates a **tenant**, which is a dedicated instance of the service representing a specific organization in the cloud.

* **Domains:** By default, a tenant is assigned a domain ending in `.onmicrosoft.com`. However, organizations can verify and add their own **custom domains** (e.g., contoso.com) to replace the default domain.
* **Administration:** The service is managed via the **Microsoft Entra admin center** (entra.microsoft.com). The creator of the tenant becomes the first user with the **Global Administrator** role, giving them the highest level of access.

#### 3. Identity and Access Management

Entra ID provides granular tools to manage various identity types:

* **Users:** It manages **Member users** (employees) and **Guest users** (external partners/vendors invited via B2B collaboration). User profiles contain properties like job titles and usage locations, which are essential for assigning licenses.
* **Groups:** To manage permissions efficiently, Entra ID uses groups.
  * **Security Groups:** Used to manage access to resources like applications. They support nesting (groups within groups) and **dynamic membership**, where users are automatically added based on rules (e.g., "Department equals DevOps").
  * **M365 Groups:** Designed for collaboration tools like shared mailboxes and calendars.
* **Administrative Units:** These allow organizations to subdivide the directory (e.g., by department or geography) and delegate administrative power to specific users over only that subset, rather than the entire directory.

#### 4. Device Management

Entra ID manages device identities to ensure security across different ownership models:

* **Entra Registered:** For personal devices (BYOD) where users access work resources (e.g., accessing email on a personal phone).
* **Entra ID Joined:** For corporate-owned devices fully managed by the organization in the cloud.
* **Entra Hybrid Joined:** For devices that exist on-premises in a traditional Active Directory but are also synchronized to the cloud to allow for management and conditional access.

#### 5. Hybrid Identity with Entra Connect

For organizations with existing on-premises infrastructure, Entra ID offers a bridge called **Microsoft Entra Connect**. This tool synchronizes on-premises Active Directory users, groups, and devices to Entra ID, creating a **hybrid identity**. It supports different authentication methods:

* **Password Hash Synchronization:** Synchronizes a hash of the user's password to the cloud, allowing authentication to happen entirely in Entra ID.
* **Pass-through Authentication:** Validates passwords against the on-premises Active Directory using software agents, keeping the authentication process on-premises.
* **Federation:** Hands off authentication to a separate federation service (like AD FS).

#### 6. Licensing

Entra ID operates on a tiered licensing model:

* **Free:** Basic features included with cloud services like Azure or M365.
* **Premium (P1/P2):** Required for advanced features such as **dynamic groups**, custom branding, and advanced security attributes.
* **Entra Suite:** A governance license covering privileged identity management and entitlement management.

In summary, Microsoft Entra ID is the central "command center" for modern identity management, allowing organizations to control who has access to what, enforce security policies, and manage identities across cloud, on-premises, and hybrid environments.

***

Based on the provided sources, managing **authorization** in Microsoft Entra ID involves granting authenticated users specific permissions to access resources. This process is grounded in the **Zero Trust** principle of "Least Privilege," ensuring users have only the minimum access required to perform their tasks for only as long as necessary,.

Here are the primary methods and strategies for managing authorization in Microsoft Entra ID:

#### 1. Role-Based Access Control (RBAC)

The primary method for managing authorization is assigning **roles** to users or groups.

* **Built-in Roles:** Entra ID comes with many predefined roles. The highest level is the **Global Administrator**, which has full access to the environment. Other specific roles, such as **User Administrator** or **Application Administrator**, can be assigned to limit scope.
* **Custom Roles:** If built-in roles do not meet specific needs, administrators can create **custom roles**. This involves selecting specific permissions (e.g., ability to read application properties or delete policies) from a list of available permissions and bundling them into a new role,.
* **Assignment Methods:** Roles can be assigned to individual users or to groups. Assigning a role to a group ensures that any user added to that group automatically inherits the permissions, and loses them when removed,.

#### 2. Group Management

Groups are essential for organizing users and managing access efficiently.

* **Security Groups:** These are best used for managing access to resources like applications and licensing,. They support **nesting** (adding a group inside another group), though nesting is not possible if the parent group has role assignments enabled or is a dynamic group.
* **Microsoft 365 Groups:** These are used primarily for collaboration tools (shared mailboxes, calendars, SharePoint sites) and only allow user accounts as members,.
* **Dynamic Membership:** Instead of manually adding users, you can create **Dynamic Groups**. Membership is determined by a query based on user properties (e.g., `JobTitle` starts with "Dev" and `Department` equals "DevOps"),. This automates authorization; if a user’s attributes change, their access is automatically updated.
* **Role-Assignable Groups:** When creating a group, you must decide immediately if it will be used to assign Entra roles (setting `Microsoft Entra Roles` to "Yes"). This setting cannot be changed after the group is created,.

#### 3. Administrative Units (Delegated Administration)

To avoid giving an administrator blanket permission over the entire organization, you can use **Administrative Units** to restrict the scope of authorization.

* **Concept:** An Administrative Unit is a container for specific users, groups, or devices (e.g., "HR Team" or a specific geographic region),.
* **Scoped Roles:** You can assign a role, such as User Administrator, to a specific user _only_ over that Administrative Unit. This allows the admin to manage only the users within that unit, rather than the entire directory,.

#### 4. Custom Security Attributes

For more granular access control, Entra ID allows the use of **Custom Security Attributes**.

* **Definition:** These are business-specific attributes (e.g., "Project Code," "Clearance Level") defined by the organization.
* **Use Case:** These attributes extend user profiles and can be used to support advanced authorization scenarios, such as **Conditional Access** policies (e.g., blocking access to an app unless the user has a "High" security clearance).
* **Management:** Managing these attributes requires specific roles, such as **Attribute Definition Administrator** (to create them) and **Assignment Administrator** (to assign them to users),. Global Administrators do not have access to these attributes by default.

#### 5. Entitlement Management and Governance

To further automate and control authorization, Entra ID offers governance features (often requiring a **P2** or **Entra Suite** license).

* **Entitlement Management:** This feature automates the process of requesting, approving, and expiring access, ensuring users have "just enough access" and "just in time" access.
* **Privileged Identity Management (PIM):** While not detailed deeply in the provided text, the sources mention that PIM is part of the governance suite used to manage high-level access permissions.

#### 6. Guest and External Access Settings

Authorization can also be managed at the tenant level for external users (B2B):

* **Guest Access Levels:** Administrators can restrict what external guests can see. Options range from "Most Inclusive" (same access as members) to "Most Restrictive" (guests cannot see directory properties of other users),.
* **Cross-Tenant Access:** You can configure settings to allow users from partner tenants to access your resources using their own credentials via B2B direct connect.

***

Based on the provided sources, here is how you can create a custom role in Microsoft Entra ID and the details regarding licensing.

#### How to Create a Custom Role

To create a custom role when the built-in roles do not meet your specific needs, follow these steps in the **Microsoft Entra admin center**:

1. **Navigate to Roles:** Go to the **Roles & admins** blade within the portal.
2. **Start Creation:** Select **New custom role**.
3. **Define Basics:** Provide a **name** and **description** for the role (e.g., "Project 1 App Permissions") to ensure other administrators understand its purpose.
4. **Choose Setup Method:** You can either **clone** an existing custom role (if you have one) or **Start from scratch**.
5. **Select Permissions:**
   * Go to the **Permissions** tab.
   * Search or filter for the specific resources you need (e.g., filtering for "applications" to find permissions related to app policies or reading properties).
   * Select the specific permissions required for the role.
6. **Finalize:** Click **Next** to review your settings and then click **Create** to finish the process.

Once created, this custom role will appear in your list of roles and can be assigned to users or groups just like built-in roles.

#### Do Custom Roles Need P1/P2 Licenses?

**Based on the provided sources:** The sources do not explicitly state whether **Custom Roles** specifically require a P1 or P2 license in the same way they explicitly state that **Company Branding** and **Custom Security Attributes** are P1/P2 features. However, the sources do note generally that the **Free** edition is for basic services, while **Premium (P1/P2)** licenses are required if you are looking to "add additional features" and advanced capabilities.

**Information not from the sources:** Please note that according to standard Microsoft Entra ID documentation, **Custom Roles** are indeed a feature that requires a **Microsoft Entra ID P1 or P2 license**. You should verify your specific licensing agreement to ensure coverage.

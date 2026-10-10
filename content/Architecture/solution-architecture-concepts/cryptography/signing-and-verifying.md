---
title: "Signing and Verifying"
tags: [architecture, cryptography, signing-and-verifying]
date: 2026-01-30
description: "Steps to Create a Signature"
---

# Signing and Verifying

"https://pagefault.blog/2019/04/22/how-to-sign-and-verify-using-openssl/"

**Steps to Create a Signature**

1.  **Generate a Private Key:**

    Bash

    ```
    # Generate 4096-bit RSA private key and extract public key
    openssl genrsa -out key.pem 4096

    ```

    This creates a 2048-bit RSA private key and stores it in the file `private.key`.

2.  **Generate a Public Key:**

    Bash

    ```
    openssl rsa -in key.pem -pubout > key.pub
    ```

    This extracts the corresponding public key from your private key and stores it in `public.key`.

3.  **Create signature:**

    Bash

    ```
    openssl dgst -sign key.pem -keyform PEM -sha256 -out data.zip.sign -binary data.zip
    ```

    This generates a hash and then signs it using the private key

4.  **verify signature:**

    Bash

    ```
    openssl dgst -verify key.pub -keyform PEM -sha256 -signature data.zip.sign -binary data.zip
    Verified OK
    ```

## Across the wiki

- [[Kubernetes/concepts/L07-security/03-encryption-identity/08-tls-mtls|TLS and mTLS in Kubernetes]] — TLS and certificates (Kubernetes)
- [[AWS/security/certificate-manager/README|AWS ACM]] — TLS and certificates (AWS)
- [[Kubernetes/concepts/L07-security/01-api-access/04-certificates|Certificates]] — TLS and certificates (Kubernetes)
- [[Kubernetes/guides/networking/service-mesh|Service Mesh]] — TLS and certificates (Kubernetes)

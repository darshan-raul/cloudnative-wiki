---
title: "Amazon Lightsail"
description: "Select a Lightsail instance, database or container plan with current bundle discovery, custom-domain TLS and realistic availability trade-offs."
tags:
  - cloud/aws/compute
date: 2026-10-12
---

# Amazon Lightsail

Lightsail simplifies selected instance, database, container and networking workflows. A bundle is not an unlimited all-inclusive bill or a universal replacement for [[AWS/compute/ec2/README|EC2]], [[AWS/compute/ecs/README|ECS]] or [[AWS/databases/rds/README|RDS]].

## Product distinctions

Instances are VMs with customer-managed OS/application patching. Managed databases support selected MySQL/PostgreSQL offerings, not managed MongoDB. Installing MongoDB on a VM makes it your operational responsibility.

High-availability database plans provide a synchronous standby in another AZ. Suitability depends on availability, compatibility, backup and operational requirements; do not categorically call all Lightsail databases non-production.

Container services support a defined multi-container deployment model, not the Kubernetes API or an EKS-equivalent service mesh. Inspect actual scaling, networking and port constraints.

## Discover instead of copying obsolete plans

```bash
aws lightsail get-blueprints --region us-east-1
aws lightsail get-bundles --region us-east-1
aws lightsail get-relational-database-bundles --region us-east-1
```

Select active, compatible blueprint/bundle IDs for the desired Region and IPv4/IPv6 offering. Current examples include a \$15 standard database and \$18 load balancer, but these are not a universal price for every plan/Region. Add overage, snapshots, attached storage, distributions and other selected features from the current tariff.

## Sandbox website exercise

Prerequisites: sandbox access, budget, a chosen blueprint/bundle/AZ and a domain only if testing TLS.

1. Create one small instance using the console's selected blueprint/plan. Record its name, AZ, IPs and billing dimensions.
2. Restrict administration sources; allow only intended web ports. Check both Lightsail public firewall and guest firewall.
3. Publish a nonsensitive test page, inspect service logs and test from an allowed client.
4. Create a snapshot, restore a separate disposable instance and verify the page/data. A snapshot success response alone is not a restore test.
5. If testing a load balancer, attach instances by their documented names, configure health, request a certificate for your **custom domain**, validate DNS and test HTTPS.

Lightsail load balancers support validated certificates for custom domains. They are not limited to a Lightsail-owned domain. Review domain validation and renewal, and ensure application redirects do not expose an unintended backend.

Failure exercise: change only the sandbox guest service/port and distinguish failed health checks from DNS/firewall/TLS failures. Record the corrective action.

## Cleanup and decisions

Delete only the lab load balancer, restored/source instances, snapshots, dedicated static IP and domain records after confirming data is disposable. Keep externally required certificates/domains; inspect unattached addresses/storage for charges.

Choose EC2/VPC or ECS/EKS when requirements exceed Lightsail's documented network, orchestration, placement or instance-selection capabilities. Compare equal resource/availability requirements rather than dissimilar VM sizes.

## Component map and practical choices

```text
custom DNS → optional distribution/load balancer → instance or container service
                                                └→ managed database, if selected
static IP → one instance address
snapshot → separately restorable point-in-time copy
```

For a single VM, inspect the selected blueprint, bundle resources, IPv4/IPv6 behavior, transfer allowance and attached disks. The guest OS and application remain yours to patch. A static IP prevents normal instance address changes from forcing DNS edits, but an unattached address may have different billing. If you add a load balancer, check supported instance attachments, health path, custom-domain certificate validation and whether the workload requires more than one failure domain.

A managed database is its own resource and backup plan; a VM snapshot does not protect it. A container service deploys images and exposes the configured service port but does not provide Kubernetes objects, scheduling APIs or an arbitrary VPC feature set. For a migration, inventory hostname, certificate, persistent data and backup restoration before deleting the old plan.

Price a concrete design by listing each bundle and duration, outbound transfer above included allowance, extra disks/snapshots, database, load balancer and distribution. Compare EC2 or ECS only after matching CPU/memory, availability, storage durability, network requirements and operating effort. Confirm current regional bundles through the commands above rather than extrapolating an old fixed monthly total.

## References

- [Database engines](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-choosing-a-database.html).
- [HA databases](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-high-availability-databases.html).
- [Custom-domain TLS](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-tls-ssl-certificates-in-lightsail-https.html).
- [Container services](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-container-services.html).
- [Current pricing](https://aws.amazon.com/lightsail/pricing/).

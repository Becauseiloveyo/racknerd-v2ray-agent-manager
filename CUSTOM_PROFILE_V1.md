# CUSTOM PROFILE V1

This profile is for the user's own RackNerd VPS and common clients.

## Environment

- VPS: RackNerd
- OS: Debian 12
- Memory: about 1GB
- Main desktop client: v2rayN
- Main Android client: v2rayNG
- Goal: simple setup, small menu, clear diagnostics

## V1 Scope

V1 should not be a large panel or multi-stack deployment.

V1 should keep only:

1. Install or open upstream installer
2. Check service and ports
3. Show recommended client settings
4. Run platform connectivity checks
5. Repair DNS, time, firewall basics
6. Show logs

## Client Defaults

- Main port preference: 443
- Backup ports: 8443, 2053, 15593
- Mux: off
- IPv6: off or IPv4 preferred
- Fingerprint: chrome
- Desktop first test mode: global
- Android first test mode: global

## Notes

This project should improve stability and troubleshooting. It cannot promise that every network, carrier, account, or platform will always work.

# MasterV6 – Android Adaptive Mining Manager (Termux)

MasterV6 est un gestionnaire de minage pour Android via Termux conçu pour fonctionner de manière stable sur le long terme avec protection thermique et gestion batterie intégrée.

## Objectif

Fournir un environnement de minage contrôlé et adaptable pour appareils Android sans nécessiter de root.

## Fonctionnalités

- Protection thermique CPU
- Surveillance batterie
- Adaptation dynamique des threads
- Dashboard temps réel
- Cycles de maintenance contrôlés
- Installation automatisée de XMRig

## Installation

```bash
pkg install git -y
git clone https://github.com/HugoRiginal/masterV6_project.git
cd masterV6_project
chmod +x *.sh
bash setup.sh

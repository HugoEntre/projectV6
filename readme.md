cat << 'EOF' > ~/masterV6_project/README.md
# MasterV6 – Android Adaptive Mining Manager (Termux)

MasterV6 est un gestionnaire de minage pour Android (via Termux) conçu pour fonctionner sur le long terme avec une gestion intelligente des ressources système.

Le projet vise la stabilité, la transparence et la protection du matériel mobile.

---

## 🎯 Objectifs

- Stabiliser le minage sur appareil Android
- Protéger le CPU et la batterie
- Adapter dynamiquement les threads
- Maintenir une température maîtrisée
- Permettre un fonctionnement autonome longue durée

---

## ⚙️ Fonctionnalités principales

### 🛡️ Protection thermique
- Surveillance continue de la température CPU
- Pause automatique si seuil critique atteint
- Reprise progressive et contrôlée

### 🔋 Gestion batterie intelligente
- Surveillance du niveau de batterie
- Pause si batterie faible
- Support multi-capteurs batterie
- Politique thermique conservatrice (sélection de la température la plus élevée détectée)

### 🧠 Optimisation CPU
- Détection des clusters LITTLE / BIG
- Adaptation dynamique du nombre de threads
- Rotation périodique du miner
- Apprentissage du profil matériel

### 📊 Dashboard temps réel
- Hashrate actuel
- Shares acceptées
- Température CPU / batterie
- Uptime
- Progression des gains

### 🔄 Cycles de maintenance
Le bot alterne entre :
- Cycles utilisateur (minage principal)
- Cycles courts de maintenance
- Cycles de pause batterie

Cette logique vise une meilleure stabilité long terme et une usure réduite du matériel.

---

## 🛠 Installation

```bash
pkg install git -y
git clone https://github.com/HugoEntre/projectV6.git
cd masterV6_project
chmod +x *.sh
bash setup.sh
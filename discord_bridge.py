#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Passerelle Bidirectionnelle Discord <-> 3615 PICTO (Minitel)
Connectée par défaut sur le Canal D du PictoChat.
"""

import os
import json
import asyncio
import urllib.parse
import urllib.request
import discord
from discord.ext import commands, tasks

CONFIG_PATH = "/data/bridge_config.json"
DEFAULT_CONFIG = {
    "picto_url": os.getenv("PICTO_URL", "http://pictochat:8085"),
    "picto_room": os.getenv("PICTO_ROOM", "D"),
    "bot_pseudo": os.getenv("BOT_PSEUDO", "DISCORD"),
    "discord_channel_id": int(os.getenv("DISCORD_CHANNEL_ID", "0"))
}

def load_config():
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return {**DEFAULT_CONFIG, **data}
        except Exception:
            pass
    return DEFAULT_CONFIG.copy()

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)

config = load_config()
last_picto_id = 0
sent_from_discord = set()  # Anti-écho : mémorise les messages venant de Discord

# Configuration des Intents Discord (Message Content requis)
intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix="!", intents=intents, help_command=None)

# =====================================================================
# FONCTIONS DE COMMUNICATION HTTP AVEC LE SERVEUR PICTOCHAT
# =====================================================================
def http_poll_picto():
    global last_picto_id
    url = (
        f"{config['picto_url']}/api/poll?"
        f"room={config['picto_room']}&"
        f"since={last_picto_id}&"
        f"user={urllib.parse.quote(config['bot_pseudo'])}"
    )
    req = urllib.request.Request(url, headers={"User-Agent": "PictoDiscordBridge/1.0"})
    with urllib.request.urlopen(req, timeout=4) as resp:
        return json.loads(resp.read().decode("utf-8"))

def http_send_picto(user_str, msg_str):
    url = (
        f"{config['picto_url']}/api/send?"
        f"room={config['picto_room']}&"
        f"user={urllib.parse.quote(user_str)}&"
        f"msg={urllib.parse.quote(msg_str)}"
    )
    req = urllib.request.Request(url, method="POST", headers={"User-Agent": "PictoDiscordBridge/1.0"})
    with urllib.request.urlopen(req, timeout=4) as resp:
        return resp.read()

# =====================================================================
# BOUCLE DE SYNCHRONISATION PICTOCHAT -> DISCORD
# =====================================================================
@tasks.loop(seconds=2.0)
async def poll_pictochat():
    global last_picto_id
    try:
        data = await asyncio.to_thread(http_poll_picto)
        msgs = data.get("messages", [])

        # Au tout premier lancement, on cale l'ID sans spammer l'historique
        if last_picto_id == 0 and msgs:
            last_picto_id = max(m["id"] for m in msgs)
            return

        chan_id = config.get("discord_channel_id", 0)
        channel = bot.get_channel(chan_id) if chan_id else None

        for m in msgs:
            if m["id"] > last_picto_id:
                last_picto_id = m["id"]
                u = m.get("user", "INCONNU")
                t = m.get("text", "")
                sig = f"{u}|{t}"

                # Si ce message vient d'être envoyé depuis Discord, on l'ignore
                if sig in sent_from_discord:
                    sent_from_discord.discard(sig)
                    continue

                if u == "SYSTEME":
                    continue

                if channel:
                    await channel.send(f"📟 **[SALON {config['picto_room']}] `{u}`** : {t}")
    except Exception:
        pass

@bot.event
async def on_ready():
    print(f"[DISCORD BRIDGE] Connecté en tant que {bot.user}")
    print(f"[DISCORD BRIDGE] Salon PictoChat actif : {config['picto_room']} (Pseudo Minitel: {config['bot_pseudo']})")
    if not poll_pictochat.is_running():
        poll_pictochat.start()

# =====================================================================
# COMMANDES DE CONFIGURATION DU BOT SUR DISCORD
# =====================================================================
@bot.command(name="picto_aide", aliases=["picto_help"])
async def cmd_help(ctx):
    embed = (
        "📟 **COMMANDES DE LA PASSERELLE 3615 PICTO**\n"
        "- `!picto_ici` : Définit ce salon Discord comme salon lié au Minitel.\n"
        "- `!picto_canal <A|B|C|D>` : Choisit le canal PictoChat (Défaut : **D**).\n"
        "- `!picto_nom <NOM>` : Définit le nom du bot affiché dans la liste des connectés Minitel (10 car. max).\n"
        "- `!picto_statut` : Affiche la configuration actuelle et les utilisateurs connectés sur le Minitel."
    )
    await ctx.send(embed)

@bot.command(name="picto_ici")
@commands.has_permissions(manage_channels=True)
async def cmd_here(ctx):
    config["discord_channel_id"] = ctx.channel.id
    save_config(config)
    await ctx.send(f"✅ Ce salon Discord (**#{ctx.channel.name}**) est maintenant relié au **Salon {config['picto_room']}** de 3615 PICTO !")

@bot.command(name="picto_canal")
@commands.has_permissions(manage_channels=True)
async def cmd_room(ctx, room: str = "D"):
    global last_picto_id
    room = room.upper().strip()
    if room not in ("A", "B", "C", "D"):
        await ctx.send("❌ Canal invalide. Choisissez entre **A**, **B**, **C** ou **D**.")
        return
    config["picto_room"] = room
    last_picto_id = 0
    save_config(config)
    await ctx.send(f"✅ Passerelle basculée sur le **SALON {room}** du Minitel !")

@bot.command(name="picto_nom")
@commands.has_permissions(manage_channels=True)
async def cmd_name(ctx, *, new_name: str = "DISCORD"):
    clean = "".join(c for c in new_name.upper() if c.isalnum() or c in ("_", "-"))[:10]
    if not clean:
        clean = "DISCORD"
    config["bot_pseudo"] = clean
    save_config(config)
    await ctx.send(f"✅ Le bot apparaît désormais sous le pseudo **`{clean}`** dans le salon Minitel !")

@bot.command(name="picto_statut")
async def cmd_status(ctx):
    try:
        data = await asyncio.to_thread(http_poll_picto)
        users = ", ".join(data.get("users", [])) or "Aucun"
        counts = data.get("counts", {})
        c_str = f"A:{counts.get('A',0)} | B:{counts.get('B',0)} | C:{counts.get('C',0)} | D:{counts.get('D',0)}"
        chan_mention = f"<#{config['discord_channel_id']}>" if config["discord_channel_id"] else "Non configuré (`!picto_ici`)"
        msg = (
            f"📡 **ÉTAT PASSERELLE 3615 PICTO**\n"
            f"- **Salon Discord lié** : {chan_mention}\n"
            f"- **Canal Minitel actif** : Salon **{config['picto_room']}**\n"
            f"- **Nom du Bot sur Minitel** : `{config['bot_pseudo']}`\n"
            f"- **Connectés dans le Salon {config['picto_room']}** : `{users}`\n"
            f"- **Activité Globale** : `{c_str}`"
        )
        await ctx.send(msg)
    except Exception as e:
        await ctx.send(f"⚠️ Erreur de connexion au serveur PictoChat : `{e}`")

# =====================================================================
# RELAIS DES MESSAGES DISCORD -> MINITEL
# =====================================================================
@bot.event
async def on_message(message):
    if message.author.bot:
        return

    await bot.process_commands(message)

    # Si c'est une commande !picto_..., on ne l'envoie pas sur le Minitel
    if message.content.startswith("!"):
        return

    # Vérifie si le message est posté dans le salon Discord configuré
    if message.channel.id == config.get("discord_channel_id"):
        # Formatage du pseudo Discord en 10 caractères max pour le Minitel
        raw_author = message.author.display_name.upper()
        author_clean = "".join(c for c in raw_author if c.isalnum() or c in ("_", "-"))[:10] or "DISCORD"

        content = message.clean_content.strip()
        if not content and message.attachments:
            content = "[IMAGE/FICHIER DISCORD]"
        if not content:
            return

        # Découpe en tranches de 58 caractères si le message Discord est long
        chunks = [content[i:i+58] for i in range(0, min(len(content), 174), 58)]
        for chunk in chunks:
            # Enregistre la signature pour éviter l'écho en retour
            sent_from_discord.add(f"{author_clean}|{chunk.upper()}")
            try:
                await asyncio.to_thread(http_send_picto, author_clean, chunk)
            except Exception as e:
                print(f"Erreur envoi Minitel: {e}")

if __name__ == "__main__":
    token = os.getenv("DISCORD_TOKEN", "").strip()
    if not token:
        print("ERREUR : La variable d'environnement DISCORD_TOKEN est vide !")
        exit(1)
    bot.run(token)

# Professional — Recipe Profit Calculator

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/professional-recipe-studio">
    <img src="https://img.shields.io/badge/CurseForge-Download-F16436?logo=curseforge&logoColor=white" alt="CurseForge"/>
  </a>
</p>

**A World of Warcraft Anniversary (TBC) addon that shows you exactly which recipes make gold.**

Professional queries [Auctionator](https://www.curseforge.com/wow/addons/auctionator) for live auction house prices, then calculates material cost, sale price, deposit fee, and net profit for every recipe across all your crafting professions — all in one scrollable, sortable, filterable window.

---

## Screenshot

![Professional - Recipe Profit Studio](https://media.forgecdn.net/attachments/1576/314/34295379-5026-4ea2-86f2-d8a7053b8047-png.png)

---

## Requirements

| Dependency                                                       | Notes                                          |
| ---------------------------------------------------------------- | ---------------------------------------------- |
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | Required — prices are pulled from its database |
| WoW Anniversary (TBC)                                            | Interface version 20505                        |

---

## Installation

1. Download the latest release from [CurseForge](https://www.curseforge.com/wow/addons/professional-recipe-studio).
2. Extract the `Professional` folder into:
   ```
   World of Warcraft/_anniversary_/Interface/AddOns/
   ```
3. Restart WoW or reload your UI (`/reload`).

---

## Quick Start

1. Open any crafting profession window (e.g. Alchemy, Blacksmithing).
2. Type `/pc` (or `/Professional`) to open the panel.
3. Click **Scan** — recipes are read from the live trade skill window and Auctionator prices are fetched.
4. Repeat for each profession you want to track; use the **profession dropdown** to switch between them.
5. Click any **column header** to sort. Type in the **filter box** to search by name.
6. Hover any row for a full **per-reagent cost breakdown** tooltip.

---

## Columns

| Column      | Description                                |
| ----------- | ------------------------------------------ |
| Icon        | Recipe item icon                           |
| Name        | Recipe name                                |
| Learned     | Whether you know the recipe                |
| Materials   | Reagent list                               |
| Mat Cost    | Total cost to buy all materials off the AH |
| Sale Price  | Expected sell price from Auctionator       |
| Deposit Fee | AH deposit cost per listing                |
| Profit      | Sale Price − Mat Cost − Deposit            |
| Profit %    | Profit as a percentage of mat cost         |

All columns can be individually shown or hidden from the Settings panel.

---

## Filters

Click the **funnel** icon to open the filter panel:

| Filter             | Description                                           |
| ------------------ | ----------------------------------------------------- |
| Learned Only       | Hide recipes you haven't learned                      |
| Unlearned Only     | Show only recipes you don't know yet                  |
| Sellable Only      | Hide recipes with no AH sale price                    |
| Complete Mats Only | Only show recipes where all materials have prices     |
| Has Craft Savings  | Recipes where crafting beats buying the finished item |
| Only Crafted Mats  | Recipes whose materials are themselves crafted        |
| Min Profit         | Hide recipes below a gold threshold                   |
| Min Profit %       | Hide recipes below a percentage margin                |
| Min Sale Price     | Hide recipes whose sale price is too low              |
| Max Mat Cost       | Hide recipes whose materials cost too much            |

Filters can be persisted across sessions via **Keep Filters** in Settings.

---

## Supported Professions

- Alchemy
- Blacksmithing
- Enchanting
- Engineering
- Jewelcrafting
- Leatherworking
- Mining
- Tailoring

---

## Settings

Open Settings via the **cog** icon in the toolbar:

- **Auto-Open** — automatically show the panel when a profession window opens
- **Keep Filters** — save active filters between sessions
- **Theme** — choose from four UI themes:
  - Ocean Blue _(default — modern dark blue)_
  - Dark Blizzard _(classic Blizzard gold border style)_
  - Dark Black _(minimal monochrome)_
  - Professional _(dark with purple accents)_
- **Columns** — toggle individual columns on or off

Window position is saved automatically.

---

## Slash Commands

| Command         | Action                 |
| --------------- | ---------------------- |
| `/pc`           | Toggle the main window |
| `/Professional` | Toggle the main window |

---

## Author

**Gnizah** — v1.0.2  
[CurseForge Page](https://www.curseforge.com/wow/addons/professional-recipe-studio)

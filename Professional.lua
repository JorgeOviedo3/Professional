-------------------------------------------------------------------------------
-- Professional.lua  –  Recipe Profit Calculator
-- Interface: 20505 (WoW Anniversary: The Burning Crusade)
-- Requires: Auctionator
--
-- USAGE:
--   1. Open any crafting profession window
--   2. Type /pc  (or /Professional)
--   3. Click "Scan" — all recipes are read and Auctionator prices fetched
--   4. Repeat for other professions; use the dropdown to switch between them
--   5. Click any column header to sort; type in the filter box to search
--   6. Hover a row for the full per-reagent breakdown tooltip
-------------------------------------------------------------------------------

local ADDON_NAME = "Professional"
local CALLER_ID  = ADDON_NAME   -- callerID passed to Auctionator API

-- (LibRecipes / hardcoded recipe DB removed – we now rely solely on
--  the live trade skill window for recipe data.)

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================

-- Column widths (must sum to CONTENT_W)
local COL_ICON_W      = 24           -- icon column ≈ row height
local COL_NAME_W      = 180
local COL_LEARNED_W   = 70
local COL_MATS_W      = 140
local COL_MATCOST_W   = 110
local COL_SALE_W      = 110
local COL_DEPOSIT_W   = 80
local COL_PROF_W      = 110
local COL_PROF_PCT_W  = 70
local CONTENT_W  = COL_ICON_W + COL_NAME_W + COL_LEARNED_W
                 + COL_MATS_W + COL_MATCOST_W + COL_SALE_W + COL_DEPOSIT_W + COL_PROF_W + COL_PROF_PCT_W  -- 854

local SB_W       = 20    -- scrollbar width (FauxScrollFrameTemplate adds this)
local PAD        = 8     -- left/right padding inside the main frame

local FRAME_W    = CONTENT_W + SB_W + PAD * 2   -- 676
local FRAME_H    = 560
local TITLE_H    = 22    -- BasicFrameTemplate title-bar height
local TOPBAR_H   = 30
local HEADER_H   = 22
local ROW_H      = 24
local FILTER_H   = 24
local STATUS_H   = 18
local BOTTOM_PAD = FILTER_H + STATUS_H + 12

-- Computed scroll area height and how many rows fit
local SCROLL_H   = FRAME_H - TITLE_H - 6 - TOPBAR_H - 4 - HEADER_H - 2 - BOTTOM_PAD - 4
local VISIBLE_ROWS = math.floor(SCROLL_H / ROW_H)

-- ============================================================
-- SUPPORTED PROFESSIONS  (TBC crafting profs)
-- ============================================================

local CRAFTING_PROFS = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Enchanting"]     = true,
    ["Engineering"]    = true,
    ["Jewelcrafting"]  = true,
    ["Leatherworking"] = true,
    ["Mining"]         = true,
    ["Tailoring"]      = true,
}

local DATA_TABLES = {
    ["Alchemy"]       = TBC_ALCHEMY_RECIPES,
    ["Blacksmithing"] = TBC_BLACKSMITHING_RECIPES,
    ["Enchanting"]    = TBC_ENCHANTING_RECIPES,
    ["Engineering"]   = TBC_ENGINEERING_RECIPES,
    ["Jewelcrafting"] = TBC_JC_RECIPES,
    ["Leatherworking"]= TBC_LEATHERWORKING_RECIPES,
    ["Mining"]        = TBC_MINING_RECIPES,
    ["Tailoring"]     = TBC_TAILORING_RECIPES,
}

-- ============================================================
-- STATE
-- ============================================================

local cache       = {}   -- [profName] = {recipes={...}, scannedAt=N}
local selProf     = nil
local sortKey     = "profit"
local sortAsc     = false
local filterText  = ""
local displayData = {}   -- filtered+sorted slice currently shown
local pendingItemRefresh = false
local filterFrame = nil
local settingsFrame = nil
local uiConfig = {
    learnedOnly = false,
    unlearnedOnly = false,
    sellableOnly = false,
    completeMatsOnly = false,
    hasCraftSavings = false,
    hasOnlyCrafted = false,
    minProfit = nil,      -- copper
    minProfitPct = nil,   -- percent
    minSale = nil,        -- copper
    maxMatCost = nil,     -- copper
}

local DEFAULT_DB = {
    settings = {
        autoOpen = true,
        keepFilters = false,
        theme = "Ocean Blue",
        columns = {
            icon = true,
            name = true,
            learned = true,
            materials = true,
            matCost = true,
            salePrice = true,
            depositFee = true,
            profit = true,
            profitPct = true,
        },
    },
    filterConfig = {
        learnedOnly = false,
        unlearnedOnly = false,
        sellableOnly = false,
        completeMatsOnly = false,
        hasCraftSavings = false,
        hasOnlyCrafted = false,
        minProfit = nil,
        minProfitPct = nil,
        minSale = nil,
        maxMatCost = nil,
    },
    window = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    },
}

local PROF_ICONS = {
    ["ALL"]          = nil,
    ["Alchemy"]      = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]= "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]   = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]  = "Interface\\Icons\\Trade_Engineering",
    ["Jewelcrafting"]= "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"]= "Interface\\Icons\\Trade_LeatherWorking",
    ["Mining"]       = "Interface\\Icons\\Trade_Mining",
    ["Tailoring"]    = "Interface\\Icons\\Trade_Tailoring",
}

local THEMES = {
    ["Ocean Blue"] = {
        kind = "modern",
        panel = { bg = {0.08, 0.09, 0.12, 0.98}, border = {0.25, 0.27, 0.32, 1.0} },
        button = { bg = {0.12, 0.13, 0.18, 1}, border = {0.30, 0.32, 0.38, 1} },
        input = { bg = {0.10, 0.11, 0.15, 0.98}, border = {0.30, 0.32, 0.38, 1} },
        dropdown = { bg = {0.10, 0.11, 0.15, 0.98}, border = {0.30, 0.32, 0.38, 1} },
        list = { bg = {0.08, 0.09, 0.12, 0.98}, border = {0.30, 0.32, 0.38, 1} },
        row = { even = {0.10, 0.10, 0.22, 0.85}, odd = {0.07, 0.07, 0.14, 0.70} },
        header = { text = {0.9, 0.82, 0.5}, hover = {1, 1, 0.6} },
        text = {0.86, 0.89, 0.95},
        textMuted = {0.62, 0.68, 0.76},
        title = {0.90, 0.95, 1.0},
        buttonText = {0.90, 0.92, 0.98},
        buttonHover = {1, 1, 1},
        accent = {0.30, 0.30, 0.50},
        status = {0.6, 0.6, 0.6},
        dropdownArrow = "|cffc0c0c0v|r",
    },
    ["Dark Blizzard"] = {
        kind = "blizzard",
        backdrop = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        },
        bg = {0.10, 0.09, 0.07, 1},
        border = {0.80, 0.65, 0.22, 1},
        panel = { bg = {0.09, 0.08, 0.06, 1}, border = {0.70, 0.57, 0.20, 1} },
        button = { bg = {0.12, 0.10, 0.08, 1}, border = {0.80, 0.65, 0.22, 1} },
        input = { bg = {0.08, 0.07, 0.05, 1}, border = {0.70, 0.57, 0.20, 1} },
        dropdown = { bg = {0.08, 0.07, 0.05, 1}, border = {0.70, 0.57, 0.20, 1} },
        list = { bg = {0.05, 0.05, 0.05, 1}, border = {0.70, 0.57, 0.20, 1} },
        row = { even = {0.08, 0.08, 0.08, 0.85}, odd = {0.05, 0.05, 0.05, 0.75} },
        header = { text = {1.0, 0.86, 0.45}, hover = {1.0, 0.92, 0.60} },
        text = {0.95, 0.85, 0.55},
        textMuted = {0.75, 0.68, 0.45},
        title = {1.0, 0.9, 0.65},
        buttonText = {0.95, 0.85, 0.55},
        buttonHover = {1.0, 0.95, 0.70},
        accent = {0.45, 0.35, 0.12},
        status = {0.90, 0.80, 0.55},
        dropdownArrow = "|cffffd100v|r",
    },
    ["Dark Black"] = {
        kind = "blizzard",
        backdrop = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        },
        bg = {0.05, 0.05, 0.06, 0.98},
        border = {0.25, 0.25, 0.25, 1},
        panel = { bg = {0.06, 0.06, 0.07, 1}, border = {0.30, 0.30, 0.30, 1} },
        button = { bg = {0.07, 0.07, 0.08, 1}, border = {0.35, 0.35, 0.35, 1} },
        input = { bg = {0.05, 0.05, 0.06, 1}, border = {0.30, 0.30, 0.30, 1} },
        dropdown = { bg = {0.05, 0.05, 0.06, 1}, border = {0.30, 0.30, 0.30, 1} },
        list = { bg = {0.02, 0.02, 0.02, 1}, border = {0.30, 0.30, 0.30, 1} },
        row = { even = {0.06, 0.06, 0.06, 0.70}, odd = {0.04, 0.04, 0.04, 0.60} },
        header = { text = {0.85, 0.85, 0.85}, hover = {1, 1, 1} },
        text = {0.85, 0.85, 0.85},
        textMuted = {0.6, 0.6, 0.6},
        title = {0.9, 0.9, 0.9},
        buttonText = {0.85, 0.85, 0.85},
        buttonHover = {1, 1, 1},
        accent = {0.08, 0.08, 0.08},
        status = {0.7, 0.7, 0.7},
        dropdownArrow = "|cffcddcffv|r",
    },
    ["Professional"] = {
        kind = "blizzard",
        backdrop = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        },
        bg = {0.05, 0.05, 0.06, 0.98},
        border = {0.55, 0.38, 0.78, 1},
        panel = { bg = {0.06, 0.06, 0.07, 1}, border = {0.50, 0.34, 0.70, 1} },
        button = { bg = {0.07, 0.07, 0.08, 1}, border = {0.58, 0.40, 0.82, 1} },
        input = { bg = {0.05, 0.05, 0.06, 1}, border = {0.50, 0.34, 0.70, 1} },
        dropdown = { bg = {0.05, 0.05, 0.06, 1}, border = {0.50, 0.34, 0.70, 1} },
        list = { bg = {0.02, 0.02, 0.03, 1}, border = {0.50, 0.34, 0.70, 1} },
        row = { even = {0.06, 0.06, 0.06, 0.70}, odd = {0.04, 0.04, 0.04, 0.60} },
        header = { text = {0.92, 0.84, 1.0}, hover = {1.0, 0.92, 1.0} },
        text = {0.86, 0.84, 0.93},
        textMuted = {0.64, 0.62, 0.72},
        title = {0.92, 0.86, 1.0},
        buttonText = {0.88, 0.84, 0.95},
        buttonHover = {1.0, 0.95, 1.0},
        accent = {0.32, 0.22, 0.50},
        status = {0.78, 0.72, 0.88},
        dropdownArrow = "|cffb48cffv|r",
    },
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function InitDB()
    if type(ProfessionalDB) ~= "table" then ProfessionalDB = {} end
    CopyDefaults(ProfessionalDB, DEFAULT_DB)
    if ProfessionalDB.settings and ProfessionalDB.settings.keepFilters and ProfessionalDB.filterConfig then
        for k, v in pairs(ProfessionalDB.filterConfig) do
            if uiConfig[k] ~= nil then
                uiConfig[k] = v
            end
        end
    end
end

local function GetThemeKey()
    if ProfessionalDB and ProfessionalDB.settings and ProfessionalDB.settings.theme then
        return ProfessionalDB.settings.theme
    end
    return "Ocean Blue"
end

local function GetTheme()
    return THEMES[GetThemeKey()] or THEMES["Ocean Blue"]
end

local function ColumnVisible(key)
    if not ProfessionalDB or not ProfessionalDB.settings or not ProfessionalDB.settings.columns then return true end
    local val = ProfessionalDB.settings.columns[key]
    if val == nil then return true end
    return val and true or false
end

local BACKDROP_TEMPLATE = (BackdropTemplateMixin and "BackdropTemplate") or nil

local function SaveWindowPosition(frame)
    if not ProfessionalDB or not ProfessionalDB.window or not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ProfessionalDB.window.point = point or "CENTER"
    ProfessionalDB.window.relativePoint = relativePoint or "CENTER"
    ProfessionalDB.window.x = math.floor((x or 0) + 0.5)
    ProfessionalDB.window.y = math.floor((y or 0) + 0.5)
end

local function ApplyWindowPosition(frame)
    if not frame then return end
    frame:ClearAllPoints()
    if ProfessionalDB and ProfessionalDB.window and ProfessionalDB.window.point then
        local w = ProfessionalDB.window
        frame:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x or 0, w.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- UI references (set during CreateUI)
local mainFrame, scrollFrame, listFrame, statusFS, profDropdown, filterBox
local rowFrames  = {}    -- VISIBLE_ROWS fixed row frames
local headerBtns = {}
local headerBtnsByKey = {}

-- ============================================================
-- MONEY HELPERS
-- ============================================================

local function CoinIconsAbs(copper)
    if type(GetCoinTextureString) ~= "function" then
        local v = copper or 0
        local neg = v < 0
        v = math.abs(v)
        local g = math.floor(v / 10000)
        local s = math.floor((v % 10000) / 100)
        local c = v % 100
        local t = neg and "-" or ""
        if g > 0 then t = t .. g .. "g " end
        if s > 0 or g > 0 then t = t .. s .. "s " end
        t = t .. c .. "c"
        return t
    end
    if not copper or copper == 0 then return GetCoinTextureString(0) end
    return GetCoinTextureString(copper)
end

local function CoinIcons(copper)
    if copper == nil then return nil end
    local neg = copper < 0
    local str = CoinIconsAbs(math.abs(copper))
    return (neg and "-" or "") .. str
end

local function CoinsPlain(copper)
    return CoinIcons(copper)
end

local function CoinsColored(copper)
    return CoinIcons(copper)
end

local function CoinCell(copper)
    if copper == nil then return "|cff888888--|r" end
    return CoinsColored(copper)
end

local function MatCostCell(cost, complete)
    if cost == nil then return "|cff888888--|r" end
    if complete == false then
        return "|cffffcc44~|r" .. CoinIconsAbs(cost)
    end
    return CoinIconsAbs(cost)
end

local function SaleCell(salePrice)
    if salePrice == nil then
        return "|cff888888Can't sell|r"
    end
    return CoinIconsAbs(salePrice)
end

local function DepositCell(depositFee, salePrice)
    if salePrice == nil then
        return "|cff888888Can't sell|r"
    end
    return "|cffff5555-" .. CoinIconsAbs(depositFee) .. "|r"
end

local function ProfitCellDisplay(copper, complete, salePrice)
    if salePrice == nil then
        return "|cff888888Can't sell|r"
    end
    if copper == nil then return "|cff888888--|r" end
    local prefix = (complete == false) and "|cffffcc44~|r" or ""
    if copper > 0 then
        return prefix .. "|cff44ff44+" .. CoinIconsAbs(copper) .. "|r"
    elseif copper < 0 then
        return prefix .. "|cffff5555-" .. CoinIconsAbs(-copper) .. "|r"
    end
    return prefix .. "|cff888888=0c|r"
end

local function ProfitPctCell(pct, complete, salePrice)
    if salePrice == nil then
        return "|cff888888Can't sell|r"
    end
    if pct == nil then return "|cff888888--|r" end
    local prefix = (complete == false) and "|cffffcc44~|r" or ""
    local p = math.floor(pct + 0.5)
    if p > 0 then
        return prefix .. "|cff44ff44" .. p .. "%|r"
    elseif p < 0 then
        return prefix .. "|cffff5555" .. p .. "%|r"
    end
    return prefix .. "|cff8888880%|r"
end

local function ParseGoldInput(text)
    if not text or text == "" then return nil end
    local v = tonumber(text)
    if not v then return nil end
    return math.floor(v * 10000 + 0.5)
end

local function FilterRecipe(recipe)
    if uiConfig.learnedOnly and not recipe.learned then return false end
    if uiConfig.unlearnedOnly and recipe.learned then return false end
    if uiConfig.sellableOnly and recipe.salePrice == nil then return false end
    if uiConfig.completeMatsOnly and recipe.matCostComplete == false then return false end

    if uiConfig.minProfit and (recipe.profit == nil or recipe.profit < uiConfig.minProfit) then
        return false
    end
    if uiConfig.minProfitPct and (recipe.profitPct == nil or recipe.profitPct < uiConfig.minProfitPct) then
        return false
    end
    if uiConfig.minSale and (recipe.salePrice == nil or recipe.salePrice < uiConfig.minSale) then
        return false
    end
    if uiConfig.maxMatCost and (recipe.matCost == nil or recipe.matCost > uiConfig.maxMatCost) then
        return false
    end

    if uiConfig.hasCraftSavings then
        local found = false
        for _, r in ipairs(recipe.reagents or {}) do
            if r.craftSavings and r.craftSavings > 0 then
                found = true
                break
            end
        end
        if not found then return false end
    end

    if uiConfig.hasOnlyCrafted then
        local found = false
        for _, r in ipairs(recipe.reagents or {}) do
            if r.onlyCrafted then
                found = true
                break
            end
        end
        if not found then return false end
    end

    return true
end

local function ProfitCell(copper)
    if copper == nil then return "|cff888888--|r" end
    if copper > 0 then
        return "|cff44ff44+" .. CoinsPlain(copper) .. "|r"
    elseif copper < 0 then
        return "|cffff5555" .. CoinsPlain(-copper) .. "|r"
    end
    return "|cff888888=0c|r"
end

-- ============================================================
-- AUCTIONATOR PRICE LOOKUP
-- ============================================================

-- Safely call Auctionator.API.v1.GetAuctionPriceByItemLink.
-- Returns a number (copper) or nil.
local function GetAHPrice(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    if not (Auctionator
         and Auctionator.API
         and Auctionator.API.v1
         and type(Auctionator.API.v1.GetAuctionPriceByItemLink) == "function") then
        return nil
    end
    local ok, val = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink,
                          CALLER_ID, itemLink)
    if ok and type(val) == "number" and val > 0 then return val end
    return nil
end

-- Safely call Auctionator.API.v1.GetVendorPriceByItemLink.
local function GetVendorPrice(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    if not (Auctionator
         and Auctionator.API
         and Auctionator.API.v1
         and type(Auctionator.API.v1.GetVendorPriceByItemLink) == "function") then
        return nil
    end
    local ok, val = pcall(Auctionator.API.v1.GetVendorPriceByItemLink,
                          CALLER_ID, itemLink)
    if ok and type(val) == "number" and val > 0 then return val end
    return nil
end

-- Resolve item info lazily (may be nil until cache is available)
local function ResolveItemInfo(itemID)
    if not itemID then return nil end
    local ok, name, link, _, _, _, _, _, _, tex = pcall(GetItemInfo, itemID)
    if ok and link then
        return name, link, tex
    end
    return nil
end

-- Get total quantity of an item available on the auction house.
-- Returns a number (quantity) or nil.
local function GetAHQuantity(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    if not (Auctionator
         and Auctionator.API
         and Auctionator.API.v1) then
        return nil
    end
    
    -- Try GetTotalQuantityByItemLink if available; otherwise try GetQuantityByItemLink
    if type(Auctionator.API.v1.GetTotalQuantityByItemLink) == "function" then
        local ok, qty = pcall(Auctionator.API.v1.GetTotalQuantityByItemLink,
                              CALLER_ID, itemLink)
        if ok and type(qty) == "number" and qty > 0 then return qty end
    elseif type(Auctionator.API.v1.GetQuantityByItemLink) == "function" then
        local ok, qty = pcall(Auctionator.API.v1.GetQuantityByItemLink,
                              CALLER_ID, itemLink)
        if ok and type(qty) == "number" and qty > 0 then return qty end
    end
    return nil
end

-- Best unit price for a reagent: prefer AH, fall back to vendor cache
local function GetBestPrice(itemLink)
    return GetAHPrice(itemLink) or GetVendorPrice(itemLink)
end

local function GetItemIDFromItemLink(itemLink)
    if not itemLink or itemLink == "" then return nil end
    if type(GetItemInfoInstant) ~= "function" then return nil end
    local ok, itemID = pcall(GetItemInfoInstant, itemLink)
    if ok and type(itemID) == "number" then
        return itemID
    end
    return nil
end

-- ============================================================
-- CRAFTED REAGENT SUPPORT
-- ============================================================

local craftMap = nil

local function BuildCraftMap()
    if craftMap then return craftMap end
    craftMap = {}
    for profName, data in pairs(DATA_TABLES) do
        if type(data) == "table" then
            for _, v in pairs(data) do
                if v and v.resultItemID and v.materials and type(v.materials) == "table" then
                    craftMap[v.resultItemID] = {
                        prof = profName,
                        skill = v.requiredSkill,
                        materials = v.materials,
                    }
                end
            end
        end
    end
    return craftMap
end

local function ComputeCraftCost(itemID, depth, visited)
    if not itemID then return nil end
    if depth > 3 then return nil end
    visited = visited or {}
    if visited[itemID] then return nil end
    local map = BuildCraftMap()
    local entry = map[itemID]
    if not entry then return nil end

    visited[itemID] = true
    local total = 0
    for _, mat in ipairs(entry.materials) do
        if mat and mat.itemID then
            local _, matLink = ResolveItemInfo(mat.itemID)
            local price = GetAHPrice(matLink) or GetVendorPrice(matLink)
            if not price then
                local craft = ComputeCraftCost(mat.itemID, depth + 1, visited)
                if craft then
                    price = craft.cost
                else
                    visited[itemID] = nil
                    return nil
                end
            end
            total = total + (price * (mat.quantity or 1))
        end
    end
    visited[itemID] = nil
    return {
        cost = total,
        prof = entry.prof,
        skill = entry.skill,
    }
end

local function GetReagentPrice(itemID, itemLink)
    local ah = GetAHPrice(itemLink)
    if ah then
        local craft = ComputeCraftCost(itemID, 0, {})
        if craft and craft.cost and craft.cost > 0 and craft.cost < ah then
            craft.savings = ah - craft.cost
            return ah, false, craft
        end
        return ah, false, nil
    end

    local vendor = GetVendorPrice(itemLink)
    if vendor then return vendor, false, nil end

    local craft = ComputeCraftCost(itemID, 0, {})
    if craft and craft.cost and craft.cost > 0 then
        return craft.cost, true, craft
    end
    return nil, false, nil
end

-- ============================================================
-- ICON HELPERS
-- ============================================================

-- Extract icon file ID from item link using GetItemInfoInstant
local function GetIconFileIDFromItemLink(itemLink)
    if not itemLink or itemLink == "" then return nil end
    if type(GetItemInfoInstant) ~= "function" then return nil end
    
    local ok, name, link, _, _, _, _, _, _, tex, iconID = pcall(GetItemInfoInstant, itemLink)
    if ok and iconID and iconID > 0 then
        return iconID
    end
    return nil
end

-- ============================================================
-- SCAN  (reads the currently open trade skill frame)
-- ============================================================

local function ScanCurrentTradeSkill()
    local profName = GetTradeSkillLine()
    if not profName or profName == "" then
        return nil, "No profession window is open."
    end

    if not CRAFTING_PROFS[profName] then
        return nil, "'" .. profName .. "' is not a supported crafting profession."
    end

    local numSkills = GetNumTradeSkills()
    if numSkills == 0 then
        return nil, "No recipes found (trade skill returned 0 items)."
    end

    local recipes = {}

    -- If we previously scanned the actual trade skill window for this
    -- profession, remember which recipe names are already learned so we
    -- can flag them when mixing in unlearned recipes from the database.
    local learnedByName = {}
    if cache[profName] and cache[profName].recipes then
        for _, r in ipairs(cache[profName].recipes) do
            if r.name then
                learnedByName[r.name] = true
            end
        end
    end

    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)

        if skillType ~= "header" and skillName and skillName ~= "" then
            local craftedLink = GetTradeSkillItemLink(i)
            local craftedIcon = GetTradeSkillIcon and GetTradeSkillIcon(i) or nil
            local craftedItemID, craftedIconID
            if craftedLink and type(GetItemInfoInstant) == "function" then
                local ok, itemID = pcall(GetItemInfoInstant, craftedLink)
                if ok and type(itemID) == "number" then craftedItemID = itemID end
                craftedIconID = GetIconFileIDFromItemLink(craftedLink)
            end
            local numReag     = GetTradeSkillNumReagents(i)

            local reagents        = {}
            local matCostTotal    = 0
            local matCostComplete = true

            for r = 1, numReag do
                local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
                rCount = rCount or 1
                local rLink     = GetTradeSkillReagentItemLink(i, r)
                local rItemID   = GetItemIDFromItemLink(rLink)
                local unitPrice, onlyCrafted, craftInfo = GetReagentPrice(rItemID, rLink)
                local lineCost  = unitPrice and (unitPrice * rCount) or nil

                if lineCost then
                    matCostTotal = matCostTotal + lineCost
                else
                    matCostComplete = false
                end

                table.insert(reagents, {
                    name       = rName or "?",
                    link       = rLink,
                    itemID     = rItemID,
                    count      = rCount,
                    unitPrice  = unitPrice,
                    lineCost   = lineCost,
                    ahQuantity = GetAHQuantity(rLink),
                    onlyCrafted = onlyCrafted,
                    craftProf   = craftInfo and craftInfo.prof or nil,
                    craftSkill  = craftInfo and craftInfo.skill or nil,
                    craftSavings = craftInfo and craftInfo.savings or nil,
                })
            end

            local salePrice = GetAHPrice(craftedLink)
            local depositFee = salePrice and math.floor(salePrice * 0.05 + 0.5) or nil
            local netSale = (salePrice and depositFee) and (salePrice - depositFee) or salePrice
            local profit    = (netSale and matCostTotal)
                              and (netSale - matCostTotal) or nil

            local profitPct = nil
            if matCostTotal and salePrice and matCostTotal > 0 and profit then
                profitPct = profit / matCostTotal * 100
            end

            table.insert(recipes, {
                name       = skillName,
                itemLink   = craftedLink,
                icon       = craftedIcon,
                iconID     = craftedIconID,
                resultItemID = craftedItemID,
                reagents   = reagents,
                matCost    = matCostTotal,
                matCostComplete = matCostComplete,
                salePrice  = salePrice,
                depositFee = depositFee,
                profit     = profit,
                profitPct  = profitPct,
                learned    = true,
            })
        end
    end

    cache[profName] = { recipes = recipes, scannedAt = time() }
    return profName, #recipes
end

-- Re-query Auctionator for all cached recipes without reopening the trade window
local function RefreshPrices(profName)
    if profName == "ALL" then
        local totalRefreshed = 0
        for pname, pdata in pairs(cache) do
            if pdata and pdata.recipes then
                totalRefreshed = totalRefreshed + RefreshPrices(pname)
            end
        end
        return totalRefreshed
    end
    if not cache[profName] then return 0 end

    for _, recipe in ipairs(cache[profName].recipes) do
        -- Resolve result item link if missing (item info may load later)
        if (not recipe.itemLink or recipe.itemLink == "") and recipe.resultItemID then
            local name, link = ResolveItemInfo(recipe.resultItemID)
            if link then
                recipe.itemLink = link
            end
        end

        local matTotal, complete = 0, true
        for _, r in ipairs(recipe.reagents) do
            -- Resolve reagent link/name if missing
            if (not r.link or r.link == "") and r.itemID then
                local nm, link = ResolveItemInfo(r.itemID)
                if link then
                    r.link = link
                    if nm then r.name = nm end
                end
            end
            local unitPrice, onlyCrafted, craftInfo = GetReagentPrice(r.itemID, r.link)
            r.unitPrice = unitPrice
            r.lineCost  = unitPrice and (unitPrice * r.count) or nil
            r.ahQuantity = GetAHQuantity(r.link)
            r.onlyCrafted = onlyCrafted
            r.craftProf   = craftInfo and craftInfo.prof or nil
            r.craftSkill  = craftInfo and craftInfo.skill or nil
            r.craftSavings = craftInfo and craftInfo.savings or nil
            if r.lineCost then
                matTotal = matTotal + r.lineCost
            else
                complete = false
            end
        end
        recipe.matCost   = matTotal
        recipe.matCostComplete = complete
        recipe.salePrice = GetAHPrice(recipe.itemLink)
        recipe.depositFee = recipe.salePrice and math.floor(recipe.salePrice * 0.05 + 0.5) or nil
        local netSale = (recipe.salePrice and recipe.depositFee)
                        and (recipe.salePrice - recipe.depositFee) or recipe.salePrice
        recipe.profit    = (netSale and recipe.matCost)
                           and (netSale - recipe.matCost) or nil
        if recipe.matCost and recipe.salePrice and recipe.matCost > 0 then
            recipe.profitPct = (recipe.profit or 0) / recipe.matCost * 100
        else
            recipe.profitPct = nil
        end
    end

    cache[profName].scannedAt = time()
    return #cache[profName].recipes
end

-- Load recipe data from included Data_TBC files (e.g. TBC_JC_RECIPES)
-- If a profession window is open, also enrich with reagent info
-- Merges with existing cache to avoid overwriting live scan data
local function LoadRecipesFromData(profName)
    if not profName then return 0 end

    -- Map profession names to their bundled data tables
    local dataTable = DATA_TABLES[profName]
    if not dataTable or type(dataTable) ~= "table" then
        return 0
    end

    -- Start with existing recipes from cache or empty table
    local recipes = {}
    local existingByName = {}
    if cache[profName] and cache[profName].recipes then
        for _, r in ipairs(cache[profName].recipes) do
            table.insert(recipes, r)
            if r.name then existingByName[r.name] = r end
        end
    end

    -- Build a map of recipe names to reagent lists from the live trade window (if open)
    local reagentsByName = {}
    if profName == GetTradeSkillLine() then
        for i = 1, GetNumTradeSkills() do
            local skillName, skillType = GetTradeSkillInfo(i)
            if skillType ~= "header" and skillName and skillName ~= "" then
                local reagents = {}
                local numReag = GetTradeSkillNumReagents(i)
                for r = 1, numReag do
                    local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
                    rCount = rCount or 1
                    local rLink = GetTradeSkillReagentItemLink(i, r)
                    local rItemID = GetItemIDFromItemLink(rLink)
                    local unitPrice, onlyCrafted, craftInfo = GetReagentPrice(rItemID, rLink)
                    local lineCost = unitPrice and (unitPrice * rCount) or nil
                    local qty = GetAHQuantity(rLink)

                    table.insert(reagents, {
                        name       = rName or "?",
                        link       = rLink,
                        itemID     = rItemID,
                        count      = rCount,
                        unitPrice  = unitPrice,
                        lineCost   = lineCost,
                        ahQuantity = qty,
                        onlyCrafted = onlyCrafted,
                        craftProf   = craftInfo and craftInfo.prof or nil,
                        craftSkill  = craftInfo and craftInfo.skill or nil,
                        craftSavings = craftInfo and craftInfo.savings or nil,
                    })
                end
                reagentsByName[skillName] = reagents
            end
        end
    end

    -- Add bundled data recipes (merge or create new entries)
    local bundledCount = 0
    for _, v in pairs(dataTable) do
        if v and v.name and v.resultItemID then
            local existing = existingByName[v.name]
            
            if existing then
                -- Update existing entry with data enrichment (e.g., required skill, source)
                if not existing.requiredSkill then existing.requiredSkill = v.requiredSkill end
                if not existing.source then existing.source = v.source end
                if not existing.sourceDetail then existing.sourceDetail = v.sourceDetail end
            else
                -- Create new entry from bundled data
                local itemLink, icon, iconID
                local name, link, tex = ResolveItemInfo(v.resultItemID)
                if link then
                    itemLink = link
                    icon = tex
                    iconID = GetIconFileIDFromItemLink(link)
                else
                    -- Leave nil; we'll resolve later when item info is cached
                    itemLink = nil
                    icon = nil
                    iconID = nil
                end
                
                -- Prefer resultIconID from bundled data over computed iconID
                if v.resultIconID then
                    iconID = v.resultIconID
                end

                local salePrice = GetAHPrice(itemLink)
                local depositFee = salePrice and math.floor(salePrice * 0.05 + 0.5) or nil
                local reagents = reagentsByName[v.name] or {}
                
                -- If no reagents from live trade window, use bundled materials data
                if #reagents == 0 and v.materials and type(v.materials) == "table" then
                    for _, mat in ipairs(v.materials) do
                        if mat and mat.itemID then
                            local matName, matLink = ResolveItemInfo(mat.itemID)
                            local unitPrice, onlyCrafted, craftInfo = GetReagentPrice(mat.itemID, matLink)
                            local lineCost = unitPrice and (unitPrice * (mat.quantity or 1)) or nil
                            local qty = GetAHQuantity(matLink)
                            
                            table.insert(reagents, {
                                name       = matName or ("Item #" .. tostring(mat.itemID)),
                                link       = matLink,
                                itemID     = mat.itemID,
                                count      = mat.quantity or 1,
                                unitPrice  = unitPrice,
                                lineCost   = lineCost,
                                ahQuantity = qty,
                                onlyCrafted = onlyCrafted,
                                craftProf   = craftInfo and craftInfo.prof or nil,
                                craftSkill  = craftInfo and craftInfo.skill or nil,
                                craftSavings = craftInfo and craftInfo.savings or nil,
                            })
                        end
                    end
                end

                -- Compute material cost if we have reagents
                local matCostTotal = 0
                local matCostComplete = true
                for _, r in ipairs(reagents) do
                    if r.lineCost then
                        matCostTotal = matCostTotal + r.lineCost
                    else
                        matCostComplete = false
                    end
                end

                local netSale = (salePrice and depositFee) and (salePrice - depositFee) or salePrice
                local profit = (netSale and matCostTotal)
                               and (netSale - matCostTotal) or nil
                local profitPct = nil
                if matCostTotal and salePrice and matCostTotal > 0 and profit then
                    profitPct = profit / matCostTotal * 100
                end

                table.insert(recipes, {
                    name         = v.name,
                    itemLink     = itemLink,
                    icon         = icon,
                    iconID       = iconID,
                    resultItemID = v.resultItemID,
                    recipeItemID = v.recipeItemID,
                    reagents     = reagents,
                    matCost      = matCostTotal,
                    matCostComplete = matCostComplete,
                    salePrice    = salePrice,
                    depositFee   = depositFee,
                    profit       = profit,
                    profitPct    = profitPct,
                    learned      = false,
                    requiredSkill = v.requiredSkill,
                    source       = v.source,
                    sourceDetail = v.sourceDetail,
                })
                bundledCount = bundledCount + 1
            end
        end
    end

    cache[profName] = { recipes = recipes, scannedAt = time() }
    return bundledCount
end

-- ============================================================
-- FILTER + SORT  →  builds displayData
-- ============================================================

local function BuildDisplayData()
    displayData = {}
    if not selProf then return end

    local fl = strlower(filterText)
    if selProf == "ALL" then
        -- Ensure bundled data is loaded for all profs if missing
        for pname in pairs(CRAFTING_PROFS) do
            if not cache[pname] or #(cache[pname].recipes or {}) == 0 then
                LoadRecipesFromData(pname)
            end
        end
        for _, pdata in pairs(cache) do
            if pdata and pdata.recipes then
                for _, recipe in ipairs(pdata.recipes) do
                    if (fl == "" or string.find(strlower(recipe.name), fl, 1, true))
                        and FilterRecipe(recipe) then
                        table.insert(displayData, recipe)
                    end
                end
            end
        end
    else
        if not cache[selProf] or #(cache[selProf].recipes or {}) == 0 then
            LoadRecipesFromData(selProf)
        end
        if not cache[selProf] then return end
        for _, recipe in ipairs(cache[selProf].recipes) do
            if (fl == "" or string.find(strlower(recipe.name), fl, 1, true))
                and FilterRecipe(recipe) then
                table.insert(displayData, recipe)
            end
        end
    end

    -- Sort
    local INF = math.huge
    table.sort(displayData, function(a, b)
        if sortKey == "name" then
            if sortAsc then return a.name < b.name else return a.name > b.name end
        end

        local dv = sortAsc and INF or -INF
        local function val(rec, key)
            if key == "materials" then
                return rec.matCost or dv
            end
            if key == "profitPct" then
                return rec.profitPct or dv
            end
            if key == "learned" then
                return rec.learned and 1 or 0
            end
            return rec[key] or dv
        end

        local av = val(a, sortKey)
        local bv = val(b, sortKey)
        if sortAsc then return av < bv else return av > bv end
    end)
end

-- ============================================================
-- ROW TOOLTIP
-- ============================================================

local function SetRowTooltip(rowFrame, recipe)
    rowFrame:SetScript("OnEnter", function(self)
        local tip = GameTooltip
        tip:Hide()
        tip:SetOwner(mainFrame, "ANCHOR_NONE")
        tip:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 10, 0)
        tip:ClearLines()

        if recipe.itemLink then
            pcall(tip.SetHyperlink, tip, recipe.itemLink)
        else
            tip:SetText(recipe.name, 1, 1, 1)
        end

        -- Recipe Details section (from bundled data)
        if recipe.requiredSkill or recipe.source or recipe.recipeItemID then
            tip:AddLine(" ")
            tip:AddLine("Recipe Details:", 1, 0.82, 0)
            
            if recipe.recipeItemID then
                local recipeLink
                local recipePrice = nil
                local ok, name, link = pcall(GetItemInfo, recipe.recipeItemID)
                if ok and link then
                    recipeLink = link
                    recipePrice = GetAHPrice(link)
                else
                    recipeLink = "item:" .. tostring(recipe.recipeItemID)
                end
                tip:AddLine(recipeLink, 1, 1, 1)
                
                if recipePrice then
                    local recipePriceStr = CoinsPlain(recipePrice)
                    tip:AddDoubleLine("Recipe Price:", recipePriceStr,
                        1, 1, 1,  1, 1, 0.5)
                    
                    -- Calculate break-even: how many crafts to recover recipe cost
                    if recipe.profit and recipe.profit > 0 then
                        local craftNeeded = math.ceil(recipePrice / recipe.profit)
                        tip:AddDoubleLine("Crafts to Break-Even:", tostring(craftNeeded),
                            1, 1, 1,  1, 0.8, 0.2)
                    end
                end
            end
            
            if recipe.requiredSkill then
                tip:AddDoubleLine("Required Profession Level:", tostring(recipe.requiredSkill),
                    1, 1, 1,  0.8, 1, 0.8)
            end
            
        if recipe.source then
            local sourceText = recipe.source
            if recipe.sourceDetail and type(recipe.sourceDetail) == "table" then
                if #recipe.sourceDetail > 6 then
                    sourceText = sourceText .. " (Many)"
                else
                    sourceText = sourceText .. " (" .. table.concat(recipe.sourceDetail, ", ") .. ")"
                end
            end
            tip:AddDoubleLine("Source:", sourceText,
                1, 1, 1,  0.8, 1, 0.8)
        end
        end

        local function SetLastTooltipLineSmall()
            local line = _G[tip:GetName() .. "TextLeft" .. tip:NumLines()]
            if line then
                line:SetFontObject(GameFontDisableSmall)
            end
        end

        tip:AddLine(" ")
        tip:AddLine("Materials:", 1, 0.82, 0)

        for _, r in ipairs(recipe.reagents) do
            local nm = r.link or r.name
            if r.onlyCrafted then
                local craftLine = "Only crafted"
                if r.craftProf then
                    craftLine = craftLine .. ": " .. r.craftProf
                    if r.craftSkill then
                        craftLine = craftLine .. " " .. tostring(r.craftSkill)
                    end
                end
                nm = nm .. " (" .. craftLine .. ")"
            elseif r.craftSavings and r.craftSavings > 0 then
                -- show savings on a smaller, separate line below
            end
            local pr = r.lineCost and CoinsPlain(r.lineCost) or "?"
            local qty = r.ahQuantity and " (" .. r.ahQuantity .. " for sale)" or ""
            tip:AddDoubleLine(nm .. " x" .. r.count .. qty, pr,
                1, 1, 1,  1, 1, 0.5)

            if r.craftSavings and r.craftSavings > 0 then
                local totalSavings = r.craftSavings * (r.count or 1)
                local craftLine = "Craft saves " .. CoinIconsAbs(totalSavings)
                if r.craftProf then
                    craftLine = craftLine .. " (" .. r.craftProf
                    if r.craftSkill then
                        craftLine = craftLine .. " " .. tostring(r.craftSkill)
                    end
                    craftLine = craftLine .. ")"
                end
                tip:AddLine("|cff66dd66^ " .. craftLine .. "|r")
                SetLastTooltipLineSmall()
            end
        end

        tip:AddLine(" ")
        local function ProfitSummaryText(profit, pct, salePrice)
            if salePrice == nil then return "|cff888888Can't sell|r" end
            if profit == nil then return "|cff888888N/A|r" end
            local pctStr = pct and (tostring(math.floor(pct + 0.5)) .. "%") or "N/A"
            local color = profit >= 0 and "|cff44ff44" or "|cffff5555"
            return color .. CoinIcons(profit) .. " / " .. pctStr .. "|r"
        end

        local craftSavingsTotal = 0
        if recipe.reagents then
            for _, r in ipairs(recipe.reagents) do
                if r.craftSavings and r.craftSavings > 0 then
                    craftSavingsTotal = craftSavingsTotal + (r.craftSavings * (r.count or 1))
                end
            end
        end

        local craftMatCost = nil
        if recipe.matCost and craftSavingsTotal > 0 then
            craftMatCost = recipe.matCost - craftSavingsTotal
        end

        if recipe.salePrice then
            tip:AddLine("Summary (Bought):", 1, 0.82, 0)
            tip:AddDoubleLine("Total Material Cost:",
                recipe.matCost and (recipe.matCostComplete == false
                    and ("|cffffcc44~|r" .. CoinIconsAbs(recipe.matCost))
                    or ("|cffffdd66" .. CoinIconsAbs(recipe.matCost) .. "|r")) or "|cff888888N/A|r",
                1, 0.82, 0,  1, 1, 0.6)
            tip:AddDoubleLine("AH Sale Price:",
                recipe.salePrice and ("|cff66ccff" .. CoinIconsAbs(recipe.salePrice) .. "|r") or "|cff888888Can't sell|r",
                1, 0.82, 0,  0.6, 0.8, 1)
            tip:AddDoubleLine("Deposit Fee (5%):",
                recipe.salePrice and ("|cffff6666-" .. CoinIconsAbs(recipe.depositFee or 0) .. "|r") or "|cff888888Can't sell|r",
                1, 0.82, 0,  1, 0.6, 0.6)
            tip:AddDoubleLine("Profit (Raw/%):",
                ProfitSummaryText(recipe.profit, recipe.profitPct, recipe.salePrice),
                1, 0.82, 0,  1, 1, 1)

            if craftMatCost and recipe.matCost and craftMatCost < recipe.matCost then
                local netSale = (recipe.salePrice and recipe.depositFee)
                                and (recipe.salePrice - recipe.depositFee) or recipe.salePrice
                local craftProfit = (netSale and craftMatCost) and (netSale - craftMatCost) or nil
                local craftProfitPct = nil
                if craftMatCost and craftMatCost > 0 and craftProfit then
                    craftProfitPct = craftProfit / craftMatCost * 100
                end
                tip:AddLine(" ")
                tip:AddLine("Summary (Crafted):", 1, 0.82, 0)
                tip:AddDoubleLine("Total Material Cost:",
                    "|cff66dd66" .. CoinIconsAbs(craftMatCost) .. "|r",
                    1, 0.82, 0,  1, 1, 0.6)
                tip:AddDoubleLine("AH Sale Price:",
                    recipe.salePrice and ("|cff66ccff" .. CoinIconsAbs(recipe.salePrice) .. "|r") or "|cff888888Can't sell|r",
                    1, 0.82, 0,  0.6, 0.8, 1)
                tip:AddDoubleLine("Deposit Fee (5%):",
                    recipe.salePrice and ("|cffff6666-" .. CoinIconsAbs(recipe.depositFee or 0) .. "|r") or "|cff888888Can't sell|r",
                    1, 0.82, 0,  1, 0.6, 0.6)
                tip:AddDoubleLine("Profit (Raw/%):",
                    ProfitSummaryText(craftProfit, craftProfitPct, recipe.salePrice),
                    1, 0.82, 0,  1, 1, 1)
            end
        else
            tip:AddDoubleLine("Total Material Cost (Bought):",
                recipe.matCost and (recipe.matCostComplete == false
                    and ("|cffffcc44~|r" .. CoinIconsAbs(recipe.matCost))
                    or ("|cffffdd66" .. CoinIconsAbs(recipe.matCost) .. "|r")) or "|cff888888N/A|r",
                1, 0.82, 0,  1, 1, 0.6)
            if craftMatCost and recipe.matCost and craftMatCost < recipe.matCost then
                tip:AddDoubleLine("Total Material Cost (Crafted):",
                    "|cff66dd66" .. CoinIconsAbs(craftMatCost) .. "|r",
                    1, 0.82, 0,  1, 1, 0.6)
            end
        end

        if selProf and cache[selProf] then
            tip:AddLine(" ")
            tip:AddLine(
                "Prices via Auctionator (scanned " ..
                date("%H:%M", cache[selProf].scannedAt) .. ")",
                0.5, 0.5, 0.5)
        end

        local function AdjustTooltipWidthAndColumns()
            local maxW = 0
            for i = 1, tip:NumLines() do
                local l = _G["GameTooltipTextLeft" .. i]
                local r = _G["GameTooltipTextRight" .. i]
                local lw = l and l:GetStringWidth() or 0
                local rw = r and r:GetStringWidth() or 0
                local w = lw
                if rw > 0 then
                    w = lw + rw + 24
                end
                if w > maxW then maxW = w end
            end
            maxW = math.max(260, math.min(520, maxW + 20))
            tip:SetWidth(maxW)

            for i = 1, tip:NumLines() do
                local l = _G["GameTooltipTextLeft" .. i]
                local r = _G["GameTooltipTextRight" .. i]
                if r then
                    r:SetJustifyH("RIGHT")
                    r:SetWordWrap(false)
                end
                if l then
                    l:SetWordWrap(true)
                end
            end
        end

        tip:Show()
        AdjustTooltipWidthAndColumns()
        tip:Show()
        -- Force backdrop to match content height when very tall tooltips are built
        -- no manual height reflow; rely on GameTooltip sizing
        -- Keep tooltip on-screen when it gets tall
        if tip:GetBottom() and tip:GetBottom() < 0 then
            tip:ClearAllPoints()
            tip:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMRIGHT", 10, 0)
        end
        if tip.SetClampedToScreen then
            tip:SetClampedToScreen(true)
        end
        if UIParent and tip:GetRight() and UIParent:GetRight()
            and tip:GetRight() > UIParent:GetRight() then
            tip:ClearAllPoints()
            tip:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -10, 0)
        end
    end)
    rowFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================
-- LIST REFRESH  (FauxScrollFrame virtual list pattern)
-- ============================================================

local function RefreshList()
    BuildDisplayData()

    -- Status bar
    if statusFS then
        if not selProf then
            statusFS:SetText("Open a profession window and click Scan to begin.")
        elseif selProf == "ALL" then
            local totalRecipes = 0
            for _, pdata in pairs(cache) do
                if pdata and pdata.recipes then
                    totalRecipes = totalRecipes + #pdata.recipes
                end
            end
            statusFS:SetText(string.format(
                "ALL  •  %d recipes  •  %d shown",
                totalRecipes, #displayData))
        elseif not cache[selProf] then
            statusFS:SetText(selProf .. "  |  Not scanned — open the window and click Scan.")
        else
            local d = cache[selProf]
            statusFS:SetText(string.format(
                "%s  •  %d recipes  •  %d shown  •  scanned %s",
                selProf, #d.recipes, #displayData, date("%H:%M", d.scannedAt)))
        end
    end

    if not scrollFrame then return end

    local total  = #displayData
    local showEmpty = (total == 0)
    
    -- Tell FauxScrollFrame the new totals so it resizes the scrollbar thumb
    -- Use at least VISIBLE_ROWS to keep the scroll area stable on small result sets.
    local fauxTotal = (total < VISIBLE_ROWS) and VISIBLE_ROWS or total
    FauxScrollFrame_Update(scrollFrame, fauxTotal, VISIBLE_ROWS, ROW_H)
    
    -- Get the offset after update
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    
    -- Clamp scroll offset after filtering (prevents blank lists on small results)
    local maxOffset = math.max(0, total - VISIBLE_ROWS)
    if offset > maxOffset then
        FauxScrollFrame_SetOffset(scrollFrame, maxOffset)
        offset = maxOffset
    end

    -- Fill / show each visible slot (pad with empty rows to keep layout stable)
    for rowIdx = 1, VISIBLE_ROWS do
        local dataIdx = rowIdx + offset
        local row     = rowFrames[rowIdx]
        if not row then break end

        local recipe = displayData[dataIdx]
        if recipe then
            -- Alternating background
            local theme = GetTheme()
            if dataIdx % 2 == 0 then
                row.bg:SetColorTexture(unpack(theme.row and theme.row.even or {0.10, 0.10, 0.22, 0.85}))
            else
                row.bg:SetColorTexture(unpack(theme.row and theme.row.odd or {0.07, 0.07, 0.14, 0.70}))
            end
            if row.iconTex then
                row.iconTex:SetShown(ColumnVisible("icon"))
            end

            -- Icon (prefer iconID, fall back to icon path)
            -- iconID can be: a numeric file ID, a string texture name, or nil
            if recipe.iconID then
                if type(recipe.iconID) == "number" and recipe.iconID > 0 then
                    -- Numeric file ID: use SetTextureFileID
                    row.iconTex:SetTextureFileID(recipe.iconID)
                elseif type(recipe.iconID) == "string" and recipe.iconID ~= "" then
                    -- String texture name: construct full path and use SetTexture
                    row.iconTex:SetTexture("Interface\\Icons\\" .. recipe.iconID)
                else
                    -- Invalid iconID; fall back to fallback logic
                    row.iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
            else
                -- No iconID; try icon path or attempt to get from item info
                local iconPath = recipe.icon
                if not iconPath then
                    iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
                    if recipe.itemLink then
                        local ok, _, _, _, _, _, _, _, _, tex, iconID =
                            pcall(GetItemInfoInstant, recipe.itemLink)
                        if ok and iconID and iconID > 0 then
                            row.iconTex:SetTextureFileID(iconID)
                        elseif ok and tex then
                            iconPath = tex
                        end
                    elseif recipe.resultItemID then
                        local ok, _, _, _, _, _, _, _, _, tex, iconID =
                            pcall(GetItemInfoInstant, recipe.resultItemID)
                        if ok and iconID and iconID > 0 then
                            row.iconTex:SetTextureFileID(iconID)
                        elseif ok and tex then
                            iconPath = tex
                        end
                    end
                end
                if iconPath then
                    row.iconTex:SetTexture(iconPath)
                end
            end

            -- Item name (renders as a clickable hyperlink in FontStrings)
            if row.nameFS then
                row.nameFS:SetText(recipe.itemLink or recipe.name)
                row.nameFS:SetShown(ColumnVisible("name"))
            end

            -- Materials cell: list first, then cost
            local costStr = MatCostCell(recipe.matCost, recipe.matCostComplete)
            local parts = {}
            for mi, r in ipairs(recipe.reagents) do
                if mi <= 3 then
                    local part = r.name .. " x" .. r.count
                    if r.onlyCrafted then
                        part = part .. " (Only crafted)"
                    elseif r.craftSavings and r.craftSavings > 0 then
                        part = part .. " (Craft -" .. CoinIconsAbs(r.craftSavings) .. ")"
                    end
                    table.insert(parts, part)
                else
                    table.insert(parts, "…")
                    break
                end
            end
            local matStr  = table.concat(parts, ", ")
            if row.matsFS then
                row.matsFS:SetText(matStr)
                row.matsFS:SetShown(ColumnVisible("materials"))
            end

            if row.learnedFS then
                local learnedText
                if recipe.learned then
                    learnedText = "|cff44ff44Yes|r"
                else
                    learnedText = "|cffff5555No|r"
                end
                row.learnedFS:SetText(learnedText)
                row.learnedFS:SetShown(ColumnVisible("learned"))
            end

            if row.matCostFS then
                row.matCostFS:SetText(MatCostCell(recipe.matCost, recipe.matCostComplete))
                row.matCostFS:SetShown(ColumnVisible("matCost"))
            end

            if row.saleFS then
                row.saleFS:SetText(SaleCell(recipe.salePrice))
                row.saleFS:SetShown(ColumnVisible("salePrice"))
            end
            if row.depositFS then
                row.depositFS:SetText(DepositCell(recipe.depositFee, recipe.salePrice))
                row.depositFS:SetShown(ColumnVisible("depositFee"))
            end
            if row.profFS then
                row.profFS:SetText(ProfitCellDisplay(recipe.profit, recipe.matCostComplete, recipe.salePrice))
                row.profFS:SetShown(ColumnVisible("profit"))
            end

            if row.profPctFS then
                row.profPctFS:SetText(ProfitPctCell(recipe.profitPct, recipe.matCostComplete, recipe.salePrice))
                row.profPctFS:SetShown(ColumnVisible("profitPct"))
            end

            SetRowTooltip(row, recipe)
            row:Show()
        else
            -- Empty filler row to avoid layout/scrollbar glitches on small result sets
            local theme = GetTheme()
            if rowIdx % 2 == 0 then
                local c = theme.row and theme.row.even or {0.10, 0.10, 0.22, 0.35}
                row.bg:SetColorTexture(c[1], c[2], c[3], (c[4] or 0.35) * 0.5)
            else
                local c = theme.row and theme.row.odd or {0.07, 0.07, 0.14, 0.30}
                row.bg:SetColorTexture(c[1], c[2], c[3], (c[4] or 0.30) * 0.5)
            end
            row.iconTex:SetTexture(nil)
            row.iconTex:Hide()
            if row.nameFS then
                if showEmpty and rowIdx == 1 then
                    row.nameFS:SetText("|cff777777No results|r")
                else
                    row.nameFS:SetText("|cff555555--|r")
                end
                row.nameFS:SetShown(ColumnVisible("name"))
            end
            if row.matsFS then
                row.matsFS:SetText("")
                row.matsFS:SetShown(ColumnVisible("materials"))
            end
            if row.learnedFS then
                row.learnedFS:SetText("")
                row.learnedFS:SetShown(ColumnVisible("learned"))
            end
            if row.matCostFS then
                row.matCostFS:SetText("")
                row.matCostFS:SetShown(ColumnVisible("matCost"))
            end
            if row.saleFS then
                row.saleFS:SetText("")
                row.saleFS:SetShown(ColumnVisible("salePrice"))
            end
            if row.depositFS then
                row.depositFS:SetText("")
                row.depositFS:SetShown(ColumnVisible("depositFee"))
            end
            if row.profFS then
                row.profFS:SetText("")
                row.profFS:SetShown(ColumnVisible("profit"))
            end
            if row.profPctFS then
                row.profPctFS:SetText("")
                row.profPctFS:SetShown(ColumnVisible("profitPct"))
            end
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Show()
        end
    end
end

-- ============================================================
-- CREATE ONE ROW FRAME
-- (VISIBLE_ROWS of these are created; they never move – only their
--  content changes as the user scrolls via FauxScrollFrame)
-- ============================================================

local function CreateRowFrame(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)
    row:SetHeight(ROW_H)
    -- Anchor horizontally to fill the scroll area minus the scrollbar
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -(idx - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(idx - 1) * ROW_H)
    row:EnableMouse(true)

    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.07, 0.14, 0.70)
    row.bg = bg

    -- Bottom divider
    local sep = row:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.22, 0.22, 0.35, 1)
    row.sep = sep

    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_H - 4, ROW_H - 4)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.iconTex = icon

    -- Item Name
    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetPoint("LEFT",  row, "LEFT",  COL_ICON_W + 2,                  0)
    nameFS:SetPoint("RIGHT", row, "LEFT",  COL_ICON_W + COL_NAME_W - 2,     0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    -- Learned flag
    local learnedFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    learnedFS:SetWidth(COL_LEARNED_W - 8)
    learnedFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W - 4, 0)
    learnedFS:SetJustifyH("CENTER")
    row.learnedFS = learnedFS

    -- Materials (names only)
    local matsFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matsFS:SetPoint("LEFT",  row, "LEFT",  COL_ICON_W + COL_NAME_W + COL_LEARNED_W + 4,               0)
    matsFS:SetPoint("RIGHT", row, "LEFT",  COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W - 4,  0)
    matsFS:SetJustifyH("LEFT")
    matsFS:SetWordWrap(false)
    row.matsFS = matsFS

    -- Material Cost
    local matCostFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matCostFS:SetWidth(COL_MATCOST_W - 8)
    matCostFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W + COL_MATCOST_W - 4, 0)
    matCostFS:SetJustifyH("RIGHT")
    matCostFS:SetWordWrap(false)
    row.matCostFS = matCostFS

    -- Sale Price
    local saleFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saleFS:SetWidth(COL_SALE_W - 8)
    saleFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W + COL_MATCOST_W + COL_SALE_W - 4, 0)
    saleFS:SetJustifyH("RIGHT")
    saleFS:SetWordWrap(false)
    row.saleFS = saleFS

    -- Deposit Fee
    local depositFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    depositFS:SetWidth(COL_DEPOSIT_W - 8)
    depositFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W + COL_MATCOST_W + COL_SALE_W + COL_DEPOSIT_W - 4, 0)
    depositFS:SetJustifyH("RIGHT")
    depositFS:SetWordWrap(false)
    row.depositFS = depositFS

    -- Profit
    local profFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profFS:SetWidth(COL_PROF_W - 8)
    profFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W + COL_MATCOST_W + COL_SALE_W + COL_DEPOSIT_W + COL_PROF_W - 4, 0)
    profFS:SetJustifyH("RIGHT")
    profFS:SetWordWrap(false)
    row.profFS = profFS

    -- Profit %
    local profPctFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profPctFS:SetWidth(COL_PROF_PCT_W - 8)
    profPctFS:SetPoint("RIGHT", row, "LEFT",
        COL_ICON_W + COL_NAME_W + COL_LEARNED_W + COL_MATS_W + COL_MATCOST_W + COL_SALE_W + COL_DEPOSIT_W + COL_PROF_W + COL_PROF_PCT_W - 4, 0)
    profPctFS:SetJustifyH("RIGHT")
    profPctFS:SetWordWrap(false)
    row.profPctFS = profPctFS

    row:Hide()
    return row
end

-- ============================================================
-- COLUMN HEADERS
-- ============================================================

local COL_DEFS = {
    { key = "icon",      label = "Icon",     width = COL_ICON_W,     align = "CENTER" },
    { key = "name",      label = "Item",     width = COL_NAME_W,     align = "LEFT"   },
    { key = "learned",   label = "Known",    width = COL_LEARNED_W,  align = "CENTER" },
    { key = "materials", label = "Materials",width = COL_MATS_W,     align = "LEFT"   },
    { key = "matCost",   label = "Mat Cost", width = COL_MATCOST_W,  align = "RIGHT"  },
    { key = "salePrice", label = "Sale",     width = COL_SALE_W,     align = "RIGHT"  },
    { key = "depositFee",label = "Deposit",  width = COL_DEPOSIT_W,  align = "RIGHT"  },
    { key = "profit",    label = "Profit",   width = COL_PROF_W,     align = "RIGHT"  },
    { key = "profitPct", label = "Profit %", width = COL_PROF_PCT_W, align = "RIGHT"  },
}

local function ApplyColumnVisibility()
    for _, col in ipairs(COL_DEFS) do
        local visible = ColumnVisible(col.key)
        local btn = headerBtnsByKey[col.key]
        if btn then
            btn:SetShown(visible)
        end
    end

    for _, row in ipairs(rowFrames) do
        if row then
            if row.iconTex then row.iconTex:SetShown(ColumnVisible("icon")) end
            if row.nameFS then row.nameFS:SetShown(ColumnVisible("name")) end
            if row.learnedFS then row.learnedFS:SetShown(ColumnVisible("learned")) end
            if row.matsFS then row.matsFS:SetShown(ColumnVisible("materials")) end
            if row.matCostFS then row.matCostFS:SetShown(ColumnVisible("matCost")) end
            if row.saleFS then row.saleFS:SetShown(ColumnVisible("salePrice")) end
            if row.depositFS then row.depositFS:SetShown(ColumnVisible("depositFee")) end
            if row.profFS then row.profFS:SetShown(ColumnVisible("profit")) end
            if row.profPctFS then row.profPctFS:SetShown(ColumnVisible("profitPct")) end
        end
    end
end

local function UpdateHeaderArrows()
    for i, col in ipairs(COL_DEFS) do
        local btn = headerBtns[i]
        if btn and btn.fs then
            local arrow = ""
            if sortKey == col.key then
                arrow = sortAsc and " ^" or " v"
            end
            btn.fs:SetText(col.label .. arrow)
        end
    end
end

local function SetSort(key)
    if sortKey == key then
        sortAsc = not sortAsc
    else
        sortKey = key
        sortAsc = (key == "name")  -- default ascending for name, descending for profit/price
        if key == "profit" or key == "salePrice" then
            sortAsc = false
        end
    end
    UpdateHeaderArrows()
    RefreshList()
end

-- ============================================================
-- PROFESSION DROPDOWN
-- ============================================================

local knownProfs = {}
local SetDropdownSelection

local function UpdateKnownProfs()
    -- Show all supported crafting professions
    knownProfs = {}
    for pname in pairs(CRAFTING_PROFS) do
        table.insert(knownProfs, pname)
    end
    table.sort(knownProfs)
    table.insert(knownProfs, 1, "ALL")
end

local function RebuildDropdown()
    if not profDropdown then return end
    UIDropDownMenu_Initialize(profDropdown, function()
        local info = UIDropDownMenu_CreateInfo()

        if #knownProfs == 0 then
            info.text     = "|cff888888(no professions found)|r"
            info.disabled = true
            UIDropDownMenu_AddButton(info)
            return
        end

        for _, pname in ipairs(knownProfs) do
            local icon = PROF_ICONS[pname]
            info.text  = pname
            info.value = pname
            info.icon = icon
            info.notCheckable = true
            info.checked = false
            info.func  = function()
                selProf = pname
                SetDropdownSelection(pname)
                -- Reset filter when changing profession
                filterText = ""
                if filterBox then filterBox:SetText("") end
                if pname == "ALL" then
                    for _, p in ipairs(knownProfs) do
                        if p ~= "ALL" then
                            if not cache[p] or #(cache[p].recipes or {}) == 0 then
                                LoadRecipesFromData(p)
                            end
                            RefreshPrices(p)
                        end
                    end
                    RefreshList()
                else
                    -- Load bundled data for this profession if not already cached
                    if not cache[pname] or #(cache[pname].recipes or {}) == 0 then
                        LoadRecipesFromData(pname)
                    end
                    -- Refresh prices for the newly selected profession
                    RefreshPrices(pname)
                    RefreshList()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

-- ============================================================
-- SIMPLE MODERN UI HELPERS
-- ============================================================

local themedPanels = {}
local themedTexts = {}
local themedButtons = {}

local function RegisterText(fs, role)
    if not fs then return end
    themedTexts[fs] = role or "text"
end

local function RoleColors(role, theme)
    if role == "button" and theme.button then return theme.button.bg, theme.button.border end
    if role == "input" and theme.input then return theme.input.bg, theme.input.border end
    if role == "dropdown" and theme.dropdown then return theme.dropdown.bg, theme.dropdown.border end
    if role == "list" and theme.list then return theme.list.bg, theme.list.border end
    if role == "panel" and theme.panel then return theme.panel.bg, theme.panel.border end
    return nil, nil
end

local function ApplyPanelTheme(frame)
    local rec = themedPanels[frame]
    if not rec then return end
    if frame.noPanel then
        if frame.SetBackdrop then frame:SetBackdrop(nil) end
        if rec.textures then
            for _, tex in pairs(rec.textures) do tex:Hide() end
        end
        return
    end
    local theme = GetTheme()

    if theme.kind == "blizzard" then
        if frame.SetBackdrop and theme.backdrop then
            frame:SetBackdrop(theme.backdrop)
            local bg = theme.bg or {1, 1, 1, 1}
            local border = theme.border or {1, 1, 1, 1}
            frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
            if rec.textures then
                for _, tex in pairs(rec.textures) do tex:Hide() end
            end
            return
        end
        if rec.textures then
            for _, tex in pairs(rec.textures) do tex:Show() end
        end
        local roleBg, roleBorder = RoleColors(rec.role, theme)
        local bgColor = roleBg or rec.bgColor or theme.bg or {0.12, 0.10, 0.06, 1}
        local borderColor = roleBorder or rec.borderColor or theme.border or {1, 0.82, 0, 1}
        rec.textures.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        rec.textures.borderTop:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        rec.textures.borderBottom:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        rec.textures.borderLeft:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        rec.textures.borderRight:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        return
    end

    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    if rec.textures then
        for _, tex in pairs(rec.textures) do tex:Show() end
    end

    local roleBg, roleBorder = RoleColors(rec.role, theme)
    local bgColor = roleBg or rec.bgColor or (theme.panel and theme.panel.bg) or {0.08, 0.09, 0.12, 0.98}
    local borderColor = roleBorder or rec.borderColor or (theme.panel and theme.panel.border) or {0.25, 0.27, 0.32, 1.0}
    rec.textures.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    rec.textures.borderTop:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    rec.textures.borderBottom:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    rec.textures.borderLeft:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    rec.textures.borderRight:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
end

local function AddPanel(frame, bgColor, borderColor, role)
    if not themedPanels[frame] then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()

        local borderTop = frame:CreateTexture(nil, "BORDER")
        borderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        borderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        borderTop:SetHeight(1)

        local borderBottom = frame:CreateTexture(nil, "BORDER")
        borderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        borderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        borderBottom:SetHeight(1)

        local borderLeft = frame:CreateTexture(nil, "BORDER")
        borderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        borderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        borderLeft:SetWidth(1)

        local borderRight = frame:CreateTexture(nil, "BORDER")
        borderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        borderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        borderRight:SetWidth(1)

        themedPanels[frame] = {
            textures = {
                bg = bg,
                borderTop = borderTop,
                borderBottom = borderBottom,
                borderLeft = borderLeft,
                borderRight = borderRight,
            },
        }
    end

    themedPanels[frame].bgColor = bgColor
    themedPanels[frame].borderColor = borderColor
    themedPanels[frame].role = role
    ApplyPanelTheme(frame)
end

local function StyleDropdown(dropdown)
    local theme = GetTheme()
    local function FixDropdownSize(dd)
        if not dd then return end
        dd:SetHeight(22)
        local name = dd:GetName()
        if name then
            local button = _G[name .. "Button"]
            local text = _G[name .. "Text"]
            if button then button:SetHeight(22) end
            if text then text:SetHeight(22) end
        end
    end

    local name = dropdown:GetName()
    if name then
        local left = _G[name .. "Left"]
        local mid = _G[name .. "Middle"]
        local right = _G[name .. "Right"]
        local button = _G[name .. "Button"]
        local text = _G[name .. "Text"]
        if left then left:Hide() end
        if mid then mid:Hide() end
        if right then right:Hide() end
        if button then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
            button:SetSize(14, 14)
            button:Show()
            button:SetHitRectInsets(-6, -6, -6, -6)
            local normal = button:GetNormalTexture()
            local pushed = button:GetPushedTexture()
            local highlight = button:GetHighlightTexture()
            if normal then normal:SetTexture(nil) end
            if pushed then pushed:SetTexture(nil) end
            if highlight then highlight:SetTexture(nil) end
        end
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", dropdown, "LEFT", 26, 0)
            text:SetPoint("RIGHT", dropdown, "RIGHT", -22, 0)
            text:SetJustifyH("LEFT")
            text:SetJustifyV("MIDDLE")
            local tc = theme.text or {0.9, 0.9, 0.9}
            text:SetTextColor(tc[1], tc[2], tc[3])
            text:SetHeight(22)
        end
    end
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnMouseDown", function(self)
        FixDropdownSize(self)
        ToggleDropDownMenu(1, nil, self, self, 0, 0)
        C_Timer.After(0, function()
            FixDropdownSize(self)
            if type(StyleDropdownList) == "function" then
                StyleDropdownList(1)
            end
        end)
    end)
    local d = theme.dropdown or theme.panel or {}
    AddPanel(dropdown, d.bg, d.border, "dropdown")
    dropdown:SetHeight(22)
    FixDropdownSize(dropdown)

    if not dropdown.arrowFS then
        local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
        arrow:SetText(theme.dropdownArrow or "|cffc0c0c0v|r")
        dropdown.arrowFS = arrow
    end
    if dropdown.arrowFS then dropdown.arrowFS:Show() end
    if not dropdown.iconTex then
        local icon = dropdown:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", dropdown, "LEFT", 6, 0)
        dropdown.iconTex = icon
    end
end

local function UpdateDropdownWidth(dropdown, text)
    if not dropdown then return end
    local name = dropdown:GetName()
    local fs = name and _G[name .. "Text"]
    local t = text or (fs and fs:GetText()) or ""
    local textW = fs and fs:GetStringWidth() or 0
    local minW = 120
    local extra = 48 -- icon + padding + arrow
    local w = math.max(minW, math.floor(textW + extra))
    UIDropDownMenu_SetWidth(dropdown, w)
    dropdown:SetSize(w + 24, 22)
end

SetDropdownSelection = function(pname)
    if not profDropdown then return end
    local label = pname or "-- Select --"
    UIDropDownMenu_SetText(profDropdown, label)
    UpdateDropdownWidth(profDropdown, label)
    profDropdown:SetHeight(22)
    if profDropdown.iconTex then
        if pname and PROF_ICONS[pname] then
            profDropdown.iconTex:SetTexture(PROF_ICONS[pname])
            profDropdown.iconTex:Show()
        elseif pname == "ALL" and type(GetSpellTexture) == "function" then
            local tex = GetSpellTexture(135988)
            if tex then
                profDropdown.iconTex:SetTexture(tex)
                profDropdown.iconTex:Show()
            else
                profDropdown.iconTex:Hide()
            end
        else
            profDropdown.iconTex:Hide()
        end
    end
end

local function StyleDropdownList(level)
    local list = _G["DropDownList" .. level]
    if not list then return end

    local theme = GetTheme()
    if not list._styled then
        local d = theme.list or theme.panel or {}
        AddPanel(list, d.bg, d.border, "list")
        list._styled = true
    end

    local border = (theme.dropdown and theme.dropdown.border) or (theme.panel and theme.panel.border) or theme.border or {0.3, 0.3, 0.3, 1}
    local hlColor, selColor, textSel, textNorm
    if theme.kind == "blizzard" then
        if GetThemeKey() == "Dark Blizzard" then
            border = {1, 0.82, 0, 0.9}
            hlColor = {1, 0.82, 0, 0.15}
            selColor = {1, 0.82, 0, 0.20}
            textSel = {1, 0.9, 0.6}
            textNorm = {1, 1, 1}
        elseif GetThemeKey() == "Professional" then
            border = {0.55, 0.38, 0.78, 0.9}
            hlColor = {0.60, 0.40, 0.90, 0.15}
            selColor = {0.45, 0.30, 0.75, 0.20}
            textSel = {0.95, 0.88, 1.0}
            textNorm = {0.86, 0.84, 0.93}
        else
            border = {0.6, 0.7, 0.9, 0.9}
            hlColor = {0.4, 0.6, 1, 0.15}
            selColor = {0.2, 0.4, 0.8, 0.20}
            textSel = {0.85, 0.92, 1}
            textNorm = {0.85, 0.85, 0.9}
        end
    else
        hlColor = {0.2, 0.6, 0.9, 0.15}
        selColor = {0.2, 0.6, 0.9, 0.20}
        textSel = {0.8, 0.95, 1}
        textNorm = {0.9, 0.9, 0.9}
    end

    for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
        local btn = _G["DropDownList" .. level .. "Button" .. i]
        if btn and btn:IsShown() then
            if btn.icon then
                btn.icon:Show()
                btn.icon:SetSize(14, 14)
                btn.icon:ClearAllPoints()
                btn.icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
            end

            btn:ClearNormalTexture()
            btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
            local hl = btn:GetHighlightTexture()
            if hl then
                hl:SetVertexColor(hlColor[1], hlColor[2], hlColor[3], hlColor[4])
                hl:SetAllPoints()
            end

            if not btn._border then
                btn._border = {}
                btn._border.top = btn:CreateTexture(nil, "OVERLAY")
                btn._border.bottom = btn:CreateTexture(nil, "OVERLAY")
                btn._border.left = btn:CreateTexture(nil, "OVERLAY")
                btn._border.right = btn:CreateTexture(nil, "OVERLAY")
                btn._border.top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                btn._border.top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                btn._border.top:SetHeight(1)
                btn._border.bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                btn._border.bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                btn._border.bottom:SetHeight(1)
                btn._border.left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                btn._border.left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                btn._border.left:SetWidth(1)
                btn._border.right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                btn._border.right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                btn._border.right:SetWidth(1)
            end
            btn._border.top:SetColorTexture(border[1], border[2], border[3], border[4])
            btn._border.bottom:SetColorTexture(border[1], border[2], border[3], border[4])
            btn._border.left:SetColorTexture(border[1], border[2], border[3], border[4])
            btn._border.right:SetColorTexture(border[1], border[2], border[3], border[4])

            if btn.value == selProf then
                if btn._selBG == nil then
                    local bg = btn:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    btn._selBG = bg
                end
                btn._selBG:SetColorTexture(selColor[1], selColor[2], selColor[3], selColor[4])
                btn._selBG:Show()
                if btn:GetFontString() then
                    btn:GetFontString():SetTextColor(textSel[1], textSel[2], textSel[3])
                    btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                end
            else
                if btn._selBG then btn._selBG:Hide() end
                if btn:GetFontString() then
                    btn:GetFontString():SetTextColor(textNorm[1], textNorm[2], textNorm[3])
                    btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10, "")
                end
            end
        end
    end
end

local function StyleEditBox(editBox)
    local name = editBox:GetName()
    if name then
        local left = _G[name .. "Left"]
        local mid = _G[name .. "Middle"]
        local right = _G[name .. "Right"]
        if left then left:Hide() end
        if mid then mid:Hide() end
        if right then right:Hide() end
    end
    if editBox.noBorder then
        if themedPanels[editBox] and themedPanels[editBox].textures then
            for _, tex in pairs(themedPanels[editBox].textures) do tex:Hide() end
        end
        if editBox.SetBackdrop then editBox:SetBackdrop(nil) end
        return
    end
    local theme = GetTheme()
    local d = theme.input or theme.panel or {}
    AddPanel(editBox, d.bg, d.border, "input")
end

local function CreateFlatButton(parent, width, height, label, iconPath)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    local theme = GetTheme()
    local d = theme.button or theme.panel or {}
    AddPanel(btn, d.bg, d.border, "button")
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(label or "")
    btn.fs = fs
    themedButtons[btn] = true
    local normal = theme.buttonText or theme.text or {0.9, 0.9, 0.9}
    local hover = theme.buttonHover or {1, 1, 1}
    btn._themeNormal = normal
    btn._themeHover = hover
    fs:SetTextColor(normal[1], normal[2], normal[3])
    if iconPath then
        btn.fs:Hide()
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetTexture(iconPath)
        btn.iconTex = icon
    end
    btn:SetScript("OnEnter", function(self)
        local c = self._themeHover or {1, 1, 1}
        if self.fs then self.fs:SetTextColor(c[1], c[2], c[3]) end
    end)
    btn:SetScript("OnLeave", function(self)
        local c = self._themeNormal or {0.9, 0.9, 0.9}
        if self.fs then self.fs:SetTextColor(c[1], c[2], c[3]) end
    end)
    function btn:SetText(text)
        self.fs:SetText(text or "")
    end
    return btn
end

local function ApplyTheme()
    local theme = GetTheme()

    for frame, _ in pairs(themedPanels) do
        ApplyPanelTheme(frame)
    end

    if profDropdown and profDropdown.arrowFS then
        profDropdown.arrowFS:SetText(theme.dropdownArrow or "|cffc0c0c0v|r")
    end
    if settingsFrame and settingsFrame.themeDropdown and settingsFrame.themeDropdown.arrowFS then
        settingsFrame.themeDropdown.arrowFS:SetText(theme.dropdownArrow or "|cffc0c0c0v|r")
    end

    if statusFS and theme.status then
        statusFS:SetTextColor(theme.status[1], theme.status[2], theme.status[3])
    end

    for btn, _ in pairs(themedButtons) do
        if btn and btn.fs then
            local normal = theme.buttonText or theme.text or {0.9, 0.9, 0.9}
            local hover = theme.buttonHover or {1, 1, 1}
            btn._themeNormal = normal
            btn._themeHover = hover
            btn.fs:SetTextColor(normal[1], normal[2], normal[3])
        end
    end

    for fs, role in pairs(themedTexts) do
        if fs and fs.SetTextColor then
            local c = theme.text or {0.9, 0.9, 0.9}
            if role == "title" then
                c = theme.title or (theme.header and theme.header.text) or c
            elseif role == "muted" then
                c = theme.textMuted or c
            end
            fs:SetTextColor(c[1], c[2], c[3])
        end
    end

    for _, btn in pairs(headerBtns) do
        if btn and btn.fs and theme.header then
            btn.fs:SetTextColor(theme.header.text[1], theme.header.text[2], theme.header.text[3])
            btn._themeNormal = theme.header.text
            btn._themeHover = theme.header.hover
        end
    end

    if profDropdown then StyleDropdown(profDropdown) end
    if settingsFrame and settingsFrame.themeDropdown then StyleDropdown(settingsFrame.themeDropdown) end
    if filterBox then StyleEditBox(filterBox) end

    if mainFrame and mainFrame.hdrBG then
        local key = GetThemeKey()
        if key == "Dark Black" then
            mainFrame.hdrBG:SetColorTexture(0.04, 0.04, 0.04, 0.9)
        elseif key == "Professional" then
            mainFrame.hdrBG:SetColorTexture(0.05, 0.04, 0.06, 0.92)
        elseif key == "Dark Blizzard" then
            mainFrame.hdrBG:SetColorTexture(0, 0, 0, 0)
        else
            mainFrame.hdrBG:SetColorTexture(0.12, 0.12, 0.24, 1.0)
        end
    end

    if mainFrame and mainFrame.colDivs then
        local key = GetThemeKey()
        local c
        if key == "Dark Black" then
            c = {0.08, 0.08, 0.08, 0.9}
        elseif key == "Professional" then
            c = {0.30, 0.22, 0.45, 0.9}
        elseif key == "Dark Blizzard" then
            c = {0.45, 0.35, 0.12, 0.9}
        else
            c = {0.3, 0.3, 0.5, 0.9}
        end
        for _, div in ipairs(mainFrame.colDivs) do
            div:SetColorTexture(c[1], c[2], c[3], c[4])
        end
    end

    if mainFrame and mainFrame.hdrLine then
        local key = GetThemeKey()
        local c
        if key == "Dark Black" then
            c = {0.08, 0.08, 0.08, 1}
        elseif key == "Professional" then
            c = {0.30, 0.22, 0.45, 1}
        elseif key == "Dark Blizzard" then
            c = {0.45, 0.35, 0.12, 1}
        else
            c = {0.3, 0.3, 0.5, 1}
        end
        mainFrame.hdrLine:SetColorTexture(c[1], c[2], c[3], c[4])
    end

    if mainFrame and mainFrame.topBar and mainFrame.hdrFrame and mainFrame.statusBar and mainFrame.filterBar then
        local key = GetThemeKey()
        local extraW = (key == "Dark Blizzard") and 6 or 0
        local extraH = (key == "Dark Blizzard") and 4 or 0
        local pad = PAD + extraW
        if mainFrame and mainFrame.baseW and mainFrame.baseH then
            if key == "Dark Blizzard" then
                mainFrame:SetSize(mainFrame.baseW + extraW * 2, mainFrame.baseH + extraH * 2)
            else
                mainFrame:SetSize(mainFrame.baseW, mainFrame.baseH)
            end
        end

        mainFrame.topBar:ClearAllPoints()
        mainFrame.topBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", pad, mainFrame.topY or 0)
        mainFrame.topBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -pad, mainFrame.topY or 0)

        mainFrame.hdrFrame:ClearAllPoints()
        mainFrame.hdrFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", pad, mainFrame.hdrY or 0)
        mainFrame.hdrFrame:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -(SB_W + pad), mainFrame.hdrY or 0)

        if mainFrame.hdrLine then
            local hdrY = mainFrame.hdrY or 0
            mainFrame.hdrLine:ClearAllPoints()
            mainFrame.hdrLine:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  pad,           hdrY - HEADER_H - 1)
            mainFrame.hdrLine:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -(SB_W + pad), hdrY - HEADER_H - 1)
        end

        if scrollFrame then
            scrollFrame:ClearAllPoints()
            scrollFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     pad,     mainFrame.scrollTopY or 0)
            scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -(pad + SB_W), mainFrame.scrollBottomY or 0)
        end
        if listFrame then
            listFrame:ClearAllPoints()
            listFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     pad,     mainFrame.scrollTopY or 0)
            listFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -(pad + SB_W), mainFrame.scrollBottomY or 0)
        end

        mainFrame.statusBar:ClearAllPoints()
        mainFrame.statusBar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  pad, 10)
        mainFrame.statusBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -pad, 10)

        mainFrame.filterBar:ClearAllPoints()
        mainFrame.filterBar:SetPoint("BOTTOMLEFT",  mainFrame.statusBar, "TOPLEFT",  0, 4)
        mainFrame.filterBar:SetPoint("BOTTOMRIGHT", mainFrame.statusBar, "TOPRIGHT", 0, 4)
    end

    if rowFrames then
        local key = GetThemeKey()
        local c
        if key == "Dark Black" then
            c = {0.08, 0.08, 0.08, 1}
        elseif key == "Professional" then
            c = {0.30, 0.22, 0.45, 1}
        elseif key == "Dark Blizzard" then
            c = {0.45, 0.35, 0.12, 1}
        else
            c = {0.22, 0.22, 0.35, 1}
        end
        local textColor = theme.text or {0.9, 0.9, 0.9}
        for _, row in ipairs(rowFrames) do
            if row and row.sep then
                row.sep:SetColorTexture(c[1], c[2], c[3], c[4])
            end
            if row and row.nameFS then
                row.nameFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.learnedFS then
                row.learnedFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.matsFS then
                row.matsFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.matCostFS then
                row.matCostFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.saleFS then
                row.saleFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.depositFS then
                row.depositFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if row and row.profFS then
                row.profFS:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
        end
    end

    if listFrame and listFrame.bg then
        local key = GetThemeKey()
        if key == "Dark Black" then
            listFrame.bg:SetColorTexture(0, 0, 0, 1)
        elseif key == "Professional" then
            listFrame.bg:SetColorTexture(0, 0, 0, 1)
        elseif key == "Dark Blizzard" then
            listFrame.bg:SetColorTexture(0.04, 0.04, 0.04, 1)
        else
            listFrame.bg:SetColorTexture(0, 0, 0, 0.35)
        end
    end

    if mainFrame and mainFrame.bg then
        local key = GetThemeKey()
        if key == "Dark Blizzard" then
            mainFrame.bg:SetColorTexture(0.09, 0.08, 0.06, 1)
        else
            mainFrame.bg:SetColorTexture(0, 0, 0, 0)
        end
    end

    if filterFrame and filterFrame.bg then
        local key = GetThemeKey()
        if key == "Dark Black" then
            filterFrame.bg:SetColorTexture(0.05, 0.05, 0.06, 1)
        elseif key == "Professional" then
            filterFrame.bg:SetColorTexture(0.05, 0.05, 0.06, 1)
        elseif key == "Dark Blizzard" then
            filterFrame.bg:SetColorTexture(0.09, 0.08, 0.06, 1)
        else
            filterFrame.bg:SetColorTexture(0, 0, 0, 0)
        end
    end

    if settingsFrame and settingsFrame.bg then
        local key = GetThemeKey()
        if key == "Dark Black" then
            settingsFrame.bg:SetColorTexture(0.05, 0.05, 0.06, 1)
        elseif key == "Professional" then
            settingsFrame.bg:SetColorTexture(0.05, 0.05, 0.06, 1)
        elseif key == "Dark Blizzard" then
            settingsFrame.bg:SetColorTexture(0.09, 0.08, 0.06, 1)
        else
            settingsFrame.bg:SetColorTexture(0, 0, 0, 0)
        end
    end

    local function ApplyFramePadding(frame, pad)
        if frame and frame.content then
            frame.content:ClearAllPoints()
            frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
            frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
        end
    end

    if GetThemeKey() == "Dark Blizzard" then
        ApplyFramePadding(filterFrame, 12)
        ApplyFramePadding(settingsFrame, 12)
    else
        ApplyFramePadding(filterFrame, 8)
        ApplyFramePadding(settingsFrame, 8)
    end


    local function ApplyCheckText(frame, color)
        if not frame or not frame.checks then return end
        for _, cb in ipairs(frame.checks) do
            if cb and cb.text then
                cb.text:SetTextColor(color[1], color[2], color[3])
            end
        end
    end

    local checkColor = theme.text or {0.9, 0.9, 0.9}
    ApplyCheckText(filterFrame, checkColor)
    ApplyCheckText(settingsFrame, checkColor)

    RefreshList()
end

local function SaveFilterConfig()
    if not ProfessionalDB or not ProfessionalDB.settings or not ProfessionalDB.settings.keepFilters then return end
    ProfessionalDB.filterConfig = ProfessionalDB.filterConfig or {}
    for k, v in pairs(uiConfig) do
        ProfessionalDB.filterConfig[k] = v
    end
end

local function SetFilterValue(key, value)
    uiConfig[key] = value
    SaveFilterConfig()
end

-- ============================================================
-- CONFIG UI
-- ============================================================

local function CreateFilterUI()
    if filterFrame then return end

    filterFrame = CreateFrame("Frame", "ProfessionalFilterFrame", UIParent, BACKDROP_TEMPLATE)
    filterFrame:SetSize(360, 360)
    filterFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    filterFrame:SetMovable(true)
    filterFrame:EnableMouse(true)
    filterFrame:SetClampedToScreen(true)
    filterFrame:RegisterForDrag("LeftButton")
    filterFrame:SetScript("OnDragStart", filterFrame.StartMoving)
    filterFrame:SetScript("OnDragStop",  filterFrame.StopMovingOrSizing)
    filterFrame:SetFrameStrata("DIALOG")
    filterFrame:SetFrameLevel(mainFrame:GetFrameLevel() + 5)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ProfessionalFilterFrame")
    end
    AddPanel(filterFrame, nil, nil, "panel")
    local filterBG = filterFrame:CreateTexture(nil, "BACKGROUND")
    filterBG:SetAllPoints()
    filterBG:SetColorTexture(0, 0, 0, 0)
    filterFrame.bg = filterBG
    local content = CreateFrame("Frame", nil, filterFrame)
    content:SetPoint("TOPLEFT", filterFrame, "TOPLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", filterFrame, "BOTTOMRIGHT", -8, 8)
    filterFrame.content = content
    filterFrame:Hide()

    local titleFS = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOP", content, "TOP", 0, -2)
    titleFS:SetText("Professional - Filters")
    RegisterText(titleFS, "title")

    local function MakeCheck(label, x, y, initial, onClick)
        local cb = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        cb:SetChecked(initial)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(label)
        cb:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
            RefreshList()
        end)
        filterFrame.checks = filterFrame.checks or {}
        table.insert(filterFrame.checks, cb)
        return cb
    end

    local function MakeEdit(label, x, y, width, setter)
        local fs = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        fs:SetText(label)
        RegisterText(fs, "label")

        local eb = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
        eb:SetSize(width, 20)
        eb:SetPoint("LEFT", fs, "RIGHT", 6, 0)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(10)
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                setter(self:GetText())
                RefreshList()
            end
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return eb
    end

    local y = -36
    local cbLearned = MakeCheck("Learned only", 16, y, uiConfig.learnedOnly, function(val)
        SetFilterValue("learnedOnly", val)
        if val then
            SetFilterValue("unlearnedOnly", false)
            if cbUnlearned then cbUnlearned:SetChecked(false) end
        end
    end)
    y = y - 24
    local cbUnlearned = MakeCheck("Unlearned only", 16, y, uiConfig.unlearnedOnly, function(val)
        SetFilterValue("unlearnedOnly", val)
        if val then
            SetFilterValue("learnedOnly", false)
            if cbLearned then cbLearned:SetChecked(false) end
        end
    end)
    y = y - 24
    local cbSellable = MakeCheck("Sellable only", 16, y, uiConfig.sellableOnly, function(val) SetFilterValue("sellableOnly", val) end)
    y = y - 24
    local cbComplete = MakeCheck("Complete mats only", 16, y, uiConfig.completeMatsOnly, function(val) SetFilterValue("completeMatsOnly", val) end)
    y = y - 24
    local cbSavings = MakeCheck("Has craft savings", 16, y, uiConfig.hasCraftSavings, function(val) SetFilterValue("hasCraftSavings", val) end)
    y = y - 24
    local cbOnlyCrafted = MakeCheck("Has only-crafted mats", 16, y, uiConfig.hasOnlyCrafted, function(val) SetFilterValue("hasOnlyCrafted", val) end)

    y = y - 26
    MakeCheck("Keep filters across sessions", 16, y, ProfessionalDB.settings.keepFilters, function(val)
        ProfessionalDB.settings.keepFilters = val
        if val then
            SaveFilterConfig()
        else
            ProfessionalDB.filterConfig = nil
        end
    end)

    y = y - 30
    local ebMinProfit = MakeEdit("Min profit (g):", 16, y, 60,
        function(txt) SetFilterValue("minProfit", ParseGoldInput(txt)) end)
    y = y - 24
    local ebMinPct = MakeEdit("Min profit %:", 16, y, 60,
        function(txt) SetFilterValue("minProfitPct", tonumber(txt)) end)
    y = y - 24
    local ebMinSale = MakeEdit("Min sale (g):", 16, y, 60,
        function(txt) SetFilterValue("minSale", ParseGoldInput(txt)) end)
    y = y - 24
    local ebMaxMat = MakeEdit("Max mat cost (g):", 16, y, 60,
        function(txt) SetFilterValue("maxMatCost", ParseGoldInput(txt)) end)

    if uiConfig.minProfit then
        ebMinProfit:SetText(string.format("%.2f", uiConfig.minProfit / 10000))
    end
    if uiConfig.minProfitPct then
        ebMinPct:SetText(tostring(uiConfig.minProfitPct))
    end
    if uiConfig.minSale then
        ebMinSale:SetText(string.format("%.2f", uiConfig.minSale / 10000))
    end
    if uiConfig.maxMatCost then
        ebMaxMat:SetText(string.format("%.2f", uiConfig.maxMatCost / 10000))
    end

    local clearBtn = CreateFlatButton(filterFrame, 90, 22, "Clear")
    clearBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 16, 12)
    clearBtn:SetScript("OnClick", function()
        SetFilterValue("learnedOnly", false)
        SetFilterValue("unlearnedOnly", false)
        SetFilterValue("sellableOnly", false)
        SetFilterValue("completeMatsOnly", false)
        SetFilterValue("hasCraftSavings", false)
        SetFilterValue("hasOnlyCrafted", false)
        SetFilterValue("minProfit", nil)
        SetFilterValue("minProfitPct", nil)
        SetFilterValue("minSale", nil)
        SetFilterValue("maxMatCost", nil)
        cbLearned:SetChecked(false)
        cbUnlearned:SetChecked(false)
        cbSellable:SetChecked(false)
        cbComplete:SetChecked(false)
        cbSavings:SetChecked(false)
        cbOnlyCrafted:SetChecked(false)
        ebMinProfit:SetText("")
        ebMinPct:SetText("")
        ebMinSale:SetText("")
        ebMaxMat:SetText("")
        SaveFilterConfig()
        filterFrame:Hide()
        RefreshList()
        filterFrame:Show()
    end)

    local closeBtn = CreateFlatButton(filterFrame, 90, 22, "Close")
    closeBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -16, 12)
    closeBtn:SetScript("OnClick", function() filterFrame:Hide() end)
    ApplyTheme()
end

local function CreateSettingsUI()
    if settingsFrame then return end

    settingsFrame = CreateFrame("Frame", "ProfessionalSettingsFrame", UIParent, BACKDROP_TEMPLATE)
    settingsFrame:SetSize(420, 420)
    settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop",  settingsFrame.StopMovingOrSizing)
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetFrameLevel(mainFrame:GetFrameLevel() + 5)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ProfessionalSettingsFrame")
    end
    AddPanel(settingsFrame, nil, nil, "panel")
    local settingsBG = settingsFrame:CreateTexture(nil, "BACKGROUND")
    settingsBG:SetAllPoints()
    settingsBG:SetColorTexture(0, 0, 0, 0)
    settingsFrame.bg = settingsBG
    local content = CreateFrame("Frame", nil, settingsFrame)
    content:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -8, 8)
    settingsFrame.content = content
    settingsFrame:Hide()

    local titleFS = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOP", content, "TOP", 0, -2)
    titleFS:SetText("Professional - Configuration")
    RegisterText(titleFS, "title")

    local function SectionTitle(text, y)
        local fs = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
        fs:SetText(text)
        RegisterText(fs, "title")
        return y - 20
    end

    local function MakeCheck(label, x, y, initial, onClick)
        local cb = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        cb:SetChecked(initial)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(label)
        cb:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
        end)
        settingsFrame.checks = settingsFrame.checks or {}
        table.insert(settingsFrame.checks, cb)
        return cb
    end

    local y = -36
    y = SectionTitle("General", y)

    MakeCheck("Open automatically with profession window", 16, y,
        ProfessionalDB.settings.autoOpen,
        function(val)
            ProfessionalDB.settings.autoOpen = val
        end)
    y = y - 28

    local autoNote = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoNote:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    autoNote:SetText("You can still open the addon with /professional.")
    RegisterText(autoNote, "muted")
    y = y - 22

    local posNote = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posNote:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    posNote:SetText("Window position is saved automatically.")
    RegisterText(posNote, "muted")
    y = y - 22

    local resetPosBtn = CreateFlatButton(settingsFrame, 120, 22, "Reset Position")
    resetPosBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    resetPosBtn:SetScript("OnClick", function()
        if not mainFrame then return end
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER")
        SaveWindowPosition(mainFrame)
    end)
    y = y - 32

    y = SectionTitle("Theme", y)
    local themeLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    themeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    themeLabel:SetText("Theme:")
    RegisterText(themeLabel, "label")

    local themeDropdown = CreateFrame("Frame", "ProfessionalThemeDropdown",
                                     settingsFrame, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("LEFT", themeLabel, "RIGHT", 6, -2)
    UIDropDownMenu_SetWidth(themeDropdown, 170)
    UIDropDownMenu_SetText(themeDropdown, GetThemeKey())
    StyleDropdown(themeDropdown)
    settingsFrame.themeDropdown = themeDropdown

    UIDropDownMenu_Initialize(themeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, name in ipairs({"Ocean Blue", "Dark Blizzard", "Dark Black", "Professional"}) do
            info.text = name
            info.value = name
            info.notCheckable = true
            info.func = function()
                ProfessionalDB.settings.theme = name
                UIDropDownMenu_SetText(themeDropdown, name)
                ApplyTheme()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    y = y - 36

    local versionNote = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionNote:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    versionNote:SetText("Version 1.0.2 - Created by Gnizah")
    RegisterText(versionNote, "muted")
    y = y - 22

    local closeBtn = CreateFlatButton(settingsFrame, 90, 22, "Close")
    closeBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -16, 12)
    closeBtn:SetScript("OnClick", function() settingsFrame:Hide() end)
    ApplyTheme()
end

-- ============================================================
-- MAIN FRAME CONSTRUCTION
-- ============================================================

local function CreateUI()

    ---------- Main Frame ----------
    mainFrame = CreateFrame("Frame", "ProfessionalFrame", UIParent, BACKDROP_TEMPLATE)
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame.baseW = FRAME_W
    mainFrame.baseH = FRAME_H
    ApplyWindowPosition(mainFrame)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWindowPosition(self)
    end)
    mainFrame:SetFrameStrata("HIGH")

    -- Allow closing the frame with ESC without intercepting all key input
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ProfessionalFrame")
    end
    mainFrame:Hide()
    mainFrame:SetScript("OnShow", function(self)
        self:SetAlpha(1)
        self:SetScale(1)
        self:SetFrameStrata("DIALOG")
        self:Raise()
    end)

    AddPanel(mainFrame, nil, nil, "panel")
    local mainBG = mainFrame:CreateTexture(nil, "BACKGROUND")
    mainBG:SetAllPoints()
    mainBG:SetColorTexture(0, 0, 0, 0)
    mainFrame.bg = mainBG

    local closeBtn = CreateFrame("Button", nil, mainFrame)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -8, -8)
    closeBtn:SetNormalFontObject("GameFontNormalSmall")
    closeBtn:SetText("X")
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        local fs = self:GetFontString()
        if fs then fs:SetTextColor(1, 0.4, 0.4) end
    end)
    closeBtn:SetScript("OnLeave", function(self)
        local fs = self:GetFontString()
        if fs then fs:SetTextColor(1, 1, 1) end
    end)

    local logoTex = mainFrame:CreateTexture(nil, "ARTWORK")
    logoTex:SetTexture("Interface\\AddOns\\Professional\\logo.tga")
    logoTex:SetSize(18, 18)
    logoTex:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -10)
    mainFrame.logoTex = logoTex

    local titleFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("LEFT", logoTex, "RIGHT", 6, 0)
    titleFS:SetText("Professional - Recipe Profit Studio")
    RegisterText(titleFS, "title")

    ---------- Top bar  (Profession dropdown, Scan, Refresh, Filter) ----------
    local topY = -(TITLE_H + 6)

    local topBar = CreateFrame("Frame", nil, mainFrame)
    topBar:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD,  topY)
    topBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -PAD, topY)
    topBar:SetHeight(TOPBAR_H)
    mainFrame.topBar = topBar
    mainFrame.topY = topY

    local profLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLabel:SetPoint("LEFT", topBar, "LEFT", 6, 0)
    profLabel:SetText("Profession:")
    RegisterText(profLabel, "label")

    profDropdown = CreateFrame("Frame", "ProfessionalProfDropdown",
                               topBar, "UIDropDownMenuTemplate")
    profDropdown:SetPoint("LEFT", profLabel, "RIGHT", 6, 0)
    UIDropDownMenu_SetWidth(profDropdown, 145)
    profDropdown:SetHeight(22)
    UIDropDownMenu_SetText(profDropdown, "-- Select --")
    StyleDropdown(profDropdown)
    SetDropdownSelection(selProf)

    -- Configuration button (right-most)
    local settingsBtn = CreateFlatButton(topBar, 26, 22, nil, "Interface\\AddOns\\Professional\\Icons\\cog.tga")
    settingsBtn.noPanel = true
    ApplyPanelTheme(settingsBtn)
    settingsBtn:SetPoint("RIGHT", topBar, "RIGHT", -6, 0)
    settingsBtn:SetScript("OnClick", function()
        CreateSettingsUI()
        if filterFrame and filterFrame:IsShown() then
            filterFrame:Hide()
        end
        if settingsFrame:IsShown() then
            settingsFrame:Hide()
        else
            settingsFrame:Show()
        end
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Configuration", 1, 0.82, 0)
        GameTooltip:AddLine("Open configuration options.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if settingsBtn.iconTex then
        settingsBtn.iconTex:SetSize(20, 20)
        settingsBtn.iconTex:SetVertexColor(1, 1, 1, 1)
    end

    -- Single Refresh button: scans live window, loads bundled data, and refreshes prices
    local refreshBtn = CreateFlatButton(topBar, 26, 22, nil, "Interface\\AddOns\\Professional\\Icons\\refresh-ccw.tga")
    refreshBtn.noPanel = true
    ApplyPanelTheme(refreshBtn)
    refreshBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    refreshBtn:SetScript("OnClick", function()
        if not selProf then
            return
        end

        local openProfName = GetTradeSkillLine()
        local scannedCount = 0
        
        -- If profession window is open and matches, scan it
        if openProfName and openProfName == selProf then
            local pname, count = ScanCurrentTradeSkill()
            if pname then
                scannedCount = count or 0
            end
        end
        
        -- Load bundled data (will merge with or supplement live data)
        local bundledCount = LoadRecipesFromData(selProf)
        
        -- Refresh Auctionator prices
        local pricesRefreshed = RefreshPrices(selProf)
        
        if scannedCount > 0 or bundledCount > 0 or pricesRefreshed > 0 then
            RefreshList()
        end
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Refresh", 1, 0.82, 0)
        GameTooltip:AddLine("Scan profession window, load bundled data, and refresh prices.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if refreshBtn.iconTex then
        refreshBtn.iconTex:SetSize(20, 20)
        refreshBtn.iconTex:SetVertexColor(1, 1, 1, 1)
    end

    -- Filter button
    local filterBtn = CreateFlatButton(topBar, 26, 22, nil, "Interface\\AddOns\\Professional\\Icons\\funnel.tga")
    filterBtn.noPanel = true
    ApplyPanelTheme(filterBtn)
    filterBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
    filterBtn:SetScript("OnClick", function()
        CreateFilterUI()
        if settingsFrame and settingsFrame:IsShown() then
            settingsFrame:Hide()
        end
        if filterFrame:IsShown() then
            filterFrame:Hide()
        else
            filterFrame:Show()
        end
    end)
    filterBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Filters", 1, 0.82, 0)
        GameTooltip:AddLine("Open filter configuration.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if filterBtn.iconTex then
        filterBtn.iconTex:SetSize(20, 20)
        filterBtn.iconTex:SetVertexColor(1, 1, 1, 1)
    end

    ---------- Column Headers ----------
    local hdrY = topY - TOPBAR_H - 4

    local hdrFrame = CreateFrame("Frame", nil, mainFrame)
    hdrFrame:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD,           hdrY)
    hdrFrame:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -(SB_W + PAD), hdrY)
    hdrFrame:SetHeight(HEADER_H)
    mainFrame.hdrFrame = hdrFrame
    mainFrame.hdrY = hdrY

    local hdrBG = hdrFrame:CreateTexture(nil, "BACKGROUND")
    hdrBG:SetAllPoints()
    hdrBG:SetColorTexture(0.12, 0.12, 0.24, 1.0)
    mainFrame.hdrBG = hdrBG
    mainFrame.colDivs = {}


    local colX = 0
    for i, col in ipairs(COL_DEFS) do
        local btn = CreateFrame("Button", nil, hdrFrame)
        btn:SetSize(col.width, HEADER_H)
        btn:SetPoint("LEFT", hdrFrame, "LEFT", colX, 0)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH(col.align)
        fs:SetJustifyV("MIDDLE")
        local theme = GetTheme()
        local normal = (theme.header and theme.header.text) or {0.9, 0.82, 0.5}
        local hover = (theme.header and theme.header.hover) or {1, 1, 0.6}
        fs:SetTextColor(normal[1], normal[2], normal[3])
        fs:SetText(col.label)
        btn.fs = fs
        btn._themeNormal = normal
        btn._themeHover = hover

        if i < #COL_DEFS then
            local div = hdrFrame:CreateTexture(nil, "ARTWORK")
            div:SetWidth(1)
            div:SetPoint("TOPLEFT",    hdrFrame, "TOPLEFT",    colX + col.width - 1, 0)
            div:SetPoint("BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", colX + col.width - 1, 0)
            div:SetColorTexture(0.3, 0.3, 0.5, 0.9)
            table.insert(mainFrame.colDivs, div)
        end

        local capturedKey = col.key
        btn:SetScript("OnClick", function() SetSort(capturedKey) end)
        btn:SetScript("OnEnter", function(self)
            local c = self._themeHover or {1, 1, 0.6}
            self.fs:SetTextColor(c[1], c[2], c[3])
        end)
        btn:SetScript("OnLeave", function(self)
            local c = self._themeNormal or {0.9, 0.82, 0.5}
            self.fs:SetTextColor(c[1], c[2], c[3])
        end)

        headerBtns[i] = btn
        headerBtnsByKey[col.key] = btn
        colX = colX + col.width
    end

    -- Show current sort arrow state on headers
    UpdateHeaderArrows()

    -- Separator line under headers
    local hdrLine = mainFrame:CreateTexture(nil, "ARTWORK")
    hdrLine:SetHeight(1)
    hdrLine:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD,           hdrY - HEADER_H - 1)
    hdrLine:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -(SB_W + PAD), hdrY - HEADER_H - 1)
    hdrLine:SetColorTexture(0.3, 0.3, 0.5, 1.0)
    mainFrame.hdrLine = hdrLine

    ---------- FauxScrollFrame (the actual scrollable list area) ----------
    --
    -- FauxScrollFrameTemplate creates a ScrollFrame that has a built-in
    -- scrollbar slider. We do NOT use SetScrollChild here. Instead we
    -- create exactly VISIBLE_ROWS child row frames that are always anchored
    -- at fixed positions inside the scrollFrame; only their content changes
    -- when the user scrolls (classic virtual-list pattern).
    --
    local scrollTop    = -(TITLE_H + 6 + TOPBAR_H + 4 + HEADER_H + 2)
    local scrollBottom = BOTTOM_PAD + 12

    scrollFrame = CreateFrame("ScrollFrame", "ProfessionalScrollFrame",
                              mainFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     PAD,     scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -(PAD + SB_W), scrollBottom)
    mainFrame.scrollTopY = scrollTop
    mainFrame.scrollBottomY = scrollBottom

    -- List container frame (rows live here, scrollbar is separate)
    listFrame = CreateFrame("Frame", nil, mainFrame)
    listFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     PAD,     scrollTop)
    listFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -(PAD + SB_W), scrollBottom)
    local listBG = listFrame:CreateTexture(nil, "BACKGROUND")
    listBG:SetAllPoints()
    listBG:SetColorTexture(0, 0, 0, 0.35)
    listFrame.bg = listBG
    listFrame:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)

    -- Wire up the vertical scroll callback
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)

    -- Build the fixed pool of row frames
    for i = 1, VISIBLE_ROWS do
        rowFrames[i] = CreateRowFrame(listFrame, i)
    end

    ---------- Status bar ----------
    local statusBar = CreateFrame("Frame", nil, mainFrame)
    statusBar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  PAD, 10)
    statusBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -PAD, 10)
    statusBar:SetHeight(STATUS_H)
    mainFrame.statusBar = statusBar
    
    statusFS = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetAllPoints()
    statusFS:SetJustifyH("LEFT")
    local theme = GetTheme()
    if theme.status then
        statusFS:SetTextColor(theme.status[1], theme.status[2], theme.status[3])
    else
        statusFS:SetTextColor(0.6, 0.6, 0.6)
    end
    statusFS:SetText("Open a crafting profession window, then click Scan.")
    
    ---------- Bottom search bar ----------
    local filterBar = CreateFrame("Frame", nil, mainFrame)
    filterBar:SetPoint("BOTTOMLEFT",  statusBar, "TOPLEFT",  0, 4)
    filterBar:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", 0, 4)
    filterBar:SetHeight(FILTER_H)
    mainFrame.filterBar = filterBar
    
    local filterLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("LEFT", filterBar, "LEFT", 0, 0)
    filterLabel:SetText("Search:")
    RegisterText(filterLabel, "label")
    
    filterBox = CreateFrame("EditBox", "ProfessionalFilterBox",
                            filterBar, "InputBoxTemplate")
    filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
    filterBox:SetPoint("RIGHT", filterBar, "RIGHT", -4, 0)
    filterBox:SetHeight(20)
    filterBox:SetAutoFocus(false)
    filterBox:SetMaxLetters(64)
    filterBox.noBorder = true
    StyleEditBox(filterBox)
    filterBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            filterText = self:GetText() or ""
            RefreshList()
        end
    end)
    filterBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        filterText = ""
        RefreshList()
        self:ClearFocus()
    end)


end  -- CreateUI()

-- ============================================================
-- EVENT HANDLER
-- ============================================================

local eventFrame = CreateFrame("Frame", "ProfessionalEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)

    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
        CreateUI()
        ApplyTheme()
        ApplyColumnVisibility()

    elseif event == "PLAYER_LOGIN" then
        UpdateKnownProfs()
        if mainFrame then RebuildDropdown() end
        print("|cffb48cffProfessional|r: succesfully loaded, type /professional to open.")

    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        -- Auto-open the Professional window when the profession UI is opened,
        -- auto-select the profession and perform an automatic scan + bundled data load.
        if not mainFrame then return end
        local pname = GetTradeSkillLine()
        if pname and pname ~= "" and CRAFTING_PROFS[pname] then
            UpdateKnownProfs()
            selProf = pname
            SetDropdownSelection(pname)
            RebuildDropdown()

            if ProfessionalDB and ProfessionalDB.settings and ProfessionalDB.settings.autoOpen == false then
                RefreshList()
                return
            end

            -- Scan the currently open trade skill window
            local scannedName, count = ScanCurrentTradeSkill()
            if scannedName then
                selProf = scannedName
                SetDropdownSelection(scannedName)
                UpdateKnownProfs()
                RebuildDropdown()
            end

            -- Also load bundled data (merges with live scan)
            local bundledCount = LoadRecipesFromData(pname)

            RefreshList()
            mainFrame:Show()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Throttle refreshes while item info is loading from cache
        if pendingItemRefresh then return end
        pendingItemRefresh = true
        C_Timer.After(0.3, function()
            pendingItemRefresh = false
            if selProf then
                RefreshPrices(selProf)
                RefreshList()
            end
        end)
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_Professional1 = "/professional"

SlashCmdList["Professional"] = function()
    if not mainFrame then return end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        UpdateKnownProfs()
        RebuildDropdown()
        RefreshList()
        mainFrame:Show()
    end
end

# Batch Redstone Output Controller

This script monitors AE2 for configured recipes (e.g., Tritanium Ingot) and only outputs a redstone signal if all inputs to the final craft are stored above a percentage threshold.

## Quick Start

Download the setup script from GitHub:

```bash
wget -f https://raw.githubusercontent.com/JosephKan3/fusion/main/setup.lua
```

Then run the setup script:

```bash
setup
```

## How It Works

- **Recipe Configuration:**
  - Recipes and their input requirements are defined in `recipes_config.lua`.
  - Example for Tritanium Ingot:
    - 288 Molten Duranium and 432 Molten Titanium per ingot.
- **Batch Threshold:**
  - The script calculates the batch size as the greater of:
    - `ceil(requested_amount * batch_percent)`
    - `ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE`
- **Redstone Output:**
  - Only outputs a redstone signal if all inputs are available for the calculated batch size.

## Configuration

- Edit `recipes_config.lua` to add or modify recipes and thresholds.
- Set `ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE` and `DEFAULT_BATCH_PERCENT` as needed.

## Usage

1. Ensure `recipes_config.lua` and `batch_controller.lua` are in the same directory as your other scripts.
2. Run the script:
   ```bash
   batch_controller
   ```
3. The script will check every 10 seconds (default) and print status to the console.

## Integration

- To connect redstone output, modify the `-- TODO: Output redstone signal here` section in `batch_controller.lua` to use your redstone I/O logic.
- You can reuse AE2 and redstone utility functions from the existing codebase.

---

**Example Calculation:**

If 90 Tritanium is requested, with a 10% batch and minimum batch size 10:

- `max(ceil(90 * 0.10), 10) = 10`
- Needs 10 _ 288 = 2880 Molten Duranium and 10 _ 432 = 4320 Molten Titanium in storage.

If 110 Tritanium is requested:

- `max(ceil(110 * 0.10), 10) = 11`
- Needs 11 _ 288 = 3168 Molten Duranium and 11 _ 432 = 4752 Molten Titanium.

---

**Customize as needed for your project!**

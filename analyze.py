import pandas as pd
import glob
import os

def compute_metrics(df):
    df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')
    
    numeric_cols = ['ups.realpower','ups.load','ups.temperature','battery.charge','battery.runtime']
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors='coerce')

    df = df.dropna(subset=['timestamp','ups.realpower'])

    if df.empty:
        return None

    df = df.sort_values('timestamp')
    df['delta_t'] = df['timestamp'].diff().dt.total_seconds().fillna(0)
    energy_wh = (df['ups.realpower'] * df['delta_t'] / 3600).sum()

    metrics = {
        'energy': energy_wh,
        'avg_power': df['ups.realpower'].mean(),
        'max_power': df['ups.realpower'].max(),
        'std_power': df['ups.realpower'].std(),
        'avg_load': df['ups.load'].mean(),
        'avg_temp': df['ups.temperature'].mean(),
        'avg_battery': df['battery.charge'].mean(),
        'max_runtime': df['battery.runtime'].max()
    }
    return metrics

all_folders = glob.glob("*NBs_*")
records = []

for folder in all_folders:
    problem_size = int(folder.split("NBs")[0])
    library = "NCCL" if "NCCL" in folder else "NVSHMEM"
    csv_files = glob.glob(os.path.join(folder, "*.csv"))

    for f in csv_files:
        try:
            df = pd.read_csv(f)
            metrics = compute_metrics(df)
            if metrics is not None:
                metrics.update({
                    'problem_size': problem_size,
                    'library': library,
                    'file': os.path.basename(f)
                })
                records.append(metrics)
            else:
                print(f"File {f} contains no valid data.")
        except Exception as e:
            print(f"Fehler bei Datei {f}: {e}")

if not records:
    raise RuntimeError("No valid Files found!")

all_data = pd.DataFrame(records)
all_data = all_data.sort_values(by=['problem_size','library']).reset_index(drop=True)

print("\nResulting Data")
print(all_data)

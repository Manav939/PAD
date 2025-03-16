#!/bin/bash --login
#$ -cwd
#$ -l v100               # Request a V100 GPU [ Default 1 GPU ]
#$ -pe smp.pe 8       # Requests 8 CPU cores

# Assuming cwd id $TMPDIR
# Assuming poetry is installed in the system & Poetry install is executed.
echo "Job is using $NGPUS GPU(s) with ID(s) $CUDA_VISIBLE_DEVICES and $NSLOTS CPU core(s)"

data_path='/path/to/data' # Absolute Path to the data directory

# Changing the working directory
cd BEAD/bead

poetry run bead -m new_project -p monotop_200_A ConvVAE

# Moving the dataset to the intended location
# Check for CSV files and move them if they exist 
if compgen -G "$data_path/*.csv" > /dev/null; then
    for file in "$data_path"/*.csv; do
        cp "$file" "bead/workspaces/monotop_200_A/data/csv"
        echo "$(basename "$file") will be used"
    done
fi

# Check for H5 files and move them if they exist
if compgen -G "$data_path/*.h5" > /dev/null; then
    for file in "$data_path"/*.h5; do
        cp "$file" "bead/workspaces/monotop_200_A/data/h5"
        echo "$(basename "$file") will be used"
    done
fi

# Converting the data to the format mentioned in the config file
poetry run bead -m convert_csv -p monotop_200_A ConvVAE

# Pre-processing the data
poetry run bead -m prepare_inputs -p monotop_200_A ConvVAE

# Array of models
model_list=("ConvVAE" "Planar_ConvVAE" "OrthogonalSylvester_ConvVAE" "HouseholderSylvester_ConvVAE" "TriangularSylvester_ConvVAE" "IAF_ConvVAE" "ConvFlow_ConvVAE" "NSFAR_ConvVAE")

for model in "${model_list[@]}"; do
    # Create a new project in the system
    poetry run bead -m new_project -p monotop_200_A "$model"

    # Set CONFIG_FILE variable
    CONFIG_FILE="bead/workspaces/monotop_200_A/$model/config.py"  # Relative path to the config file

    # Change number of epochs in config file to 500
    sed -i 's/\(c\.epochs\s*=\s*\)[0-9]\+/\1 500/' "$CONFIG_FILE"

    # Change the model name to the current model
    sed -i "s/\(c\.model_name\s*=\s*\).*/\1$model/" "$CONFIG_FILE"

    # Save the model after every hundred epochs by setting intermittent saving to True
    sed -i 's/\(c\.intermittent_model_saving\s*=\s*\).*/\1True/' "$CONFIG_FILE"

    # Set intermittent saving patience to 100
    sed -i 's/\(c\.intermittent_saving_patience\s*=\s*\)[0-9]\+/\1 100/' "$CONFIG_FILE"

    # Starting the training
    poetry run bead -m train -p monotop_200_A "$model"  # Fixed model saver in training.py as noted
    # In training.py line 463, changed helper.model_saver(model, path) to helper.save_model(model, path)

    # Detect the signals
    poetry run bead -m detect -p monotop_200_A "$model"

    # Plot the results
    poetry run bead -m plot -p monotop_200_A "$model"   # Note: some errors with this mode may still occur

    echo "Training and inference for $model is completed"
done

cp -r workspaces /path/to/results/model_results # Copying the model results to the intended location

cd $TMPDIR

cp -r *txt.o* /path/to/results/outputs # Copying the outputs to the intended location
cp -r *txt.e* /path/to/results/errors # Copying the errors to the intended location

echo "All models have been trained and tested"

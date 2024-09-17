export const handler = async (event) => {
    const states = [
      "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", 
      "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho", 
      "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", 
      "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi", 
      "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", 
      "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", 
      "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", 
      "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", "Virginia", 
      "Washington", "West Virginia", "Wisconsin", "Wyoming"];
    
    const { states: inputStates } = event;
    
    const inputStatesArray = inputStates.map(state => state.trim()).filter(Boolean);
    const guessedStates = new Set();
    let correctCount = 0;
    
    inputStatesArray.forEach(state => {
          const formattedState = state.charAt(0).toUpperCase() + state.slice(1).toLowerCase();
          if (states.includes(formattedState)) {
              guessedStates.add(formattedState);
              correctCount++;
          }
      });
    
    const response = {
        message: correctCount > 0 ? `${correctCount} correct guess${correctCount > 1 ? 'es' : ''}!` : 'No valid states guessed.',
        guessedStates: [...guessedStates].join(', ')
    }
    return response
  };
  
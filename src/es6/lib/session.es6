const save = (key, data) => {
  let sessionData = JSON.parse(sessionStorage.getItem(key));
  if (!sessionData) {
    sessionData = {};
  }
  Object.assign(sessionData, data);
  sessionStorage.setItem(key, JSON.stringify(sessionData));
};

export default { save };

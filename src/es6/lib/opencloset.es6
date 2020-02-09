const category = (id) => {
  let categoryInfo = {
    jacket:    { label: "자켓",     price: 10000 },
    pants:     { label: "팬츠",     price: 10000 },
    skirt:     { label: "스커트",   price: 10000 },
    shirt:     { label: "셔츠",     price: 5000  },
    blouse:    { label: "블라우스", price: 5000  },
    shoes:     { label: "구두",     price: 5000  },
    tie:       { label: "타이",     price: 0     },
    onepiece:  { label: "원피스",   price: 10000 },
    coat:      { label: "코트",     price: 10000 },
    waistcoat: { label: "조끼",     price: 5000  },
    belt:      { label: "벨트",     price: 2000  },
    bag:       { label: "가방",     price: 5000  },
    misc:      { label: "기타",     price: 0     },
  };

  return categoryInfo[id];
};

const commify = (num) => {
  num += "";
  let regex = /(^[+-]?\d+)(\d{3})/;
  while (regex.test(num)) {
    num = num.replace(regex, "$1,$2");
  }
  return num;
};

export default { category, commify };

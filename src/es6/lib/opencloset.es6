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

const color = (id) => {
  let colorInfo = {
    black:        "블랙",
    navy:         "네이비",
    gray:         "그레이",
    white:        "화이트",
    brown:        "브라운",
    blue:         "블루",
    red:          "레드",
    orange:       "오렌지",
    yellow:       "옐로우",
    green:        "그린",
    purple:       "퍼플",
    pink:         "핑크",
    charcoalgray: "차콜그레이",
    dark:         "어두운 계열",
    etc:          "기타",
    staff:        "직원추천",
  };

  return colorInfo[id];
};

const style = (id) => {
  let styleInfo = {
    basic:  "기본 정장",
    casual: "비지니스 캐주얼",
  };

  return styleInfo[id];
};

const gender = (id) => {
  let genderInfo = {
    male:   "남성",
    female: "여성",
  };

  return genderInfo[id];
};

const commify = (num) => {
  num += "";
  let regex = /(^[+-]?\d+)(\d{3})/;
  while (regex.test(num)) {
    num = num.replace(regex, "$1,$2");
  }
  return num;
};

const convertIdToString = (selector) => {
  $(selector).each((index, elem) => {
    let $elem = $(elem);
    let type = $elem.data("type");
    let id = $elem.text().trim();
    let val = "";
    switch (type) {
      case "gender":
        val = gender(id);
        break;
      case "color":
        val = color(id);
        break;
      case "style":
        val = style(id);
        break;
    }
    if (val) {
      $elem.text(val);
    }
  });
}

export default { category, color, style, gender, commify, convertIdToString };
